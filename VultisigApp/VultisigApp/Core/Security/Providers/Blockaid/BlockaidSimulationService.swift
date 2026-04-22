//
//  BlockaidSimulationService.swift
//  VultisigApp
//

import Foundation
import OSLog
import WalletCore

/// Combined output of a Blockaid scan call for a keysign payload: the parsed
/// balance-change simulation plus the risk validation result that drives the
/// `SecurityScannerHeaderView` above the hero. Solana scans populate only the
/// `simulation` field today (validation for Solana is served by a separate
/// `/solana/message/scan` call with `options: ["validation"]`).
struct BlockaidKeysignScanResult: Equatable {
    let simulation: BlockaidSimulationInfo?
    let scannerResult: SecurityScannerResult?

    static let empty = BlockaidKeysignScanResult(simulation: nil, scannerResult: nil)
}

/// Fetches and caches Blockaid scan results for the dApp signing hero.
///
/// A single scan underpins both the balance-change hero and (for EVM) the
/// "Scanned by Blockaid" header across the verify → sign → done screens.
/// Caching lets each screen resolve the same data without re-hitting
/// Blockaid's API. Failures are not cached so the next screen retries; empty
/// results (chain supported but no balance change or risk to report) are
/// cached to avoid refetching.
actor BlockaidSimulationService {

    static let shared = BlockaidSimulationService(
        rpcClient: BlockaidRpcClient(httpClient: HTTPClient())
    )

    private let rpcClient: BlockaidRpcClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "blockaid-simulation")

    private var cache: [CacheKey: BlockaidKeysignScanResult] = [:]
    private var inflight: [CacheKey: Task<BlockaidKeysignScanResult, Error>] = [:]

    init(rpcClient: BlockaidRpcClientProtocol) {
        self.rpcClient = rpcClient
    }

    /// Fetches the scan result for the given payload, coalescing concurrent
    /// callers and caching successful results by the per-chain cache key.
    ///
    /// Returns `.empty` when the chain is unsupported, the payload isn't a
    /// contract call (for EVM) or has no raw transactions (for Solana), or
    /// the scan fails.
    func scan(keysignPayload: KeysignPayload) async -> BlockaidKeysignScanResult {
        guard let key = CacheKey(payload: keysignPayload) else {
            logger.info("scan skipped: unsupported payload (chain=\(keysignPayload.coin.chain.ticker, privacy: .public), chainType=\(String(describing: keysignPayload.coin.chainType), privacy: .public), hasMemo=\(keysignPayload.memo?.isEmpty == false), hasSignSolana=\(keysignPayload.signSolana != nil))")
            return .empty
        }

        if let cached = cache[key] { return cached }
        if let pending = inflight[key] { return (try? await pending.value) ?? .empty }
        logger.info("scan dispatching for key=\(String(describing: key), privacy: .public)")

        let task: Task<BlockaidKeysignScanResult, Error>
        switch key {
        case .evm:
            task = makeEvmScanTask(keysignPayload: keysignPayload)
        case .solana:
            task = makeSolanaScanTask(keysignPayload: keysignPayload)
        }
        inflight[key] = task
        defer { inflight[key] = nil }

        do {
            let result = try await task.value
            cache[key] = result
            return result
        } catch {
            logger.error("scan failed: \(error.localizedDescription)")
            return .empty
        }
    }

    // MARK: - EVM

    private func makeEvmScanTask(
        keysignPayload: KeysignPayload
    ) -> Task<BlockaidKeysignScanResult, Error> {
        Task { [rpcClient, logger] () throws -> BlockaidKeysignScanResult in
            let response = try await rpcClient.simulateEVMTransaction(
                chain: keysignPayload.coin.chain,
                from: keysignPayload.coin.address,
                to: keysignPayload.toAddress,
                amount: keysignPayload.toAmount.toEvenLengthHexString(),
                data: keysignPayload.memo ?? "0x"
            )
            Self.debugLog(response: response, logger: logger)
            let simulation = BlockaidSimulationParser.parse(
                response: response,
                chain: keysignPayload.coin.chain
            )
            let scannerResult = response.toKeysignScannerResult()
            return BlockaidKeysignScanResult(
                simulation: simulation,
                scannerResult: scannerResult
            )
        }
    }

    // MARK: - Solana

    private func makeSolanaScanTask(
        keysignPayload: KeysignPayload
    ) -> Task<BlockaidKeysignScanResult, Error> {
        Task { [rpcClient, logger] () throws -> BlockaidKeysignScanResult in
            // The dApp keysign payload carries rawTransactions as base64. The
            // Blockaid simulate endpoint expects base58, per the extension's
            // getBlockaidPayloadSimulationInput resolver.
            let rawTxsBase64 = keysignPayload.signSolana?.rawTransactions ?? []
            let rawTxsBase58: [String] = rawTxsBase64.compactMap { base64 -> String? in
                guard let data = Data(base64Encoded: base64) else { return nil }
                return Base58.encodeNoCheck(data: data)
            }
            guard !rawTxsBase58.isEmpty else {
                logger.warning("solana scan aborted: rawTransactions base64 decode produced empty list (input count=\(rawTxsBase64.count))")
                return .empty
            }
            logger.info("solana scan calling rpc with \(rawTxsBase58.count) tx(s)")

            let response = try await rpcClient.simulateSolanaTransaction(
                address: keysignPayload.coin.address,
                rawTransactions: rawTxsBase58
            )
            Self.debugLog(response: response, logger: logger)
            let simulation = BlockaidSimulationParser.parseSolana(response: response)
            if simulation == nil {
                logger.info("solana parse returned nil — no diffs or unrecognized shape")
            }
            let scannerResult = response.toKeysignScannerResult()
            return BlockaidKeysignScanResult(
                simulation: simulation,
                scannerResult: scannerResult
            )
        }
    }

    // MARK: - Debug logging

    private static func debugLog(response: some Encodable, logger: Logger) {
        #if DEBUG
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let json = try? encoder.encode(response),
           let jsonString = String(data: json, encoding: .utf8) {
            logger.debug("scan response: \(jsonString, privacy: .public)")
        }
        #endif
    }

    // MARK: - Cache Key

    private enum CacheKey: Hashable {
        case evm(chain: Chain, memo: String)
        case solana(transactionsDigest: String)

        init?(payload: KeysignPayload) {
            switch payload.coin.chainType {
            case .EVM:
                guard let memo = payload.memo?.lowercased(),
                      memo.hasPrefix("0x"),
                      memo.count > 2 else { return nil }
                self = .evm(chain: payload.coin.chain, memo: memo)
            case .Solana:
                guard let txs = payload.signSolana?.rawTransactions,
                      !txs.isEmpty else { return nil }
                self = .solana(transactionsDigest: txs.joined(separator: "|"))
            default:
                return nil
            }
        }
    }
}
