//
//  BlockaidSimulationService.swift
//  VultisigApp
//

import Foundation
import OSLog
import WalletCore
import BigInt

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
    private let logger = Log.app.other

    private var cache: [CacheKey: BlockaidKeysignScanResult] = [:]
    private var inflight: [CacheKey: Task<BlockaidKeysignScanResult, Error>] = [:]

    init(rpcClient: BlockaidRpcClientProtocol) {
        self.rpcClient = rpcClient
    }

    /// Fetches the scan result for the given payload, coalescing concurrent
    /// callers and caching successful results by the per-chain cache key.
    ///
    /// Returns `.empty` when the chain is unsupported, an EVM payload cannot
    /// be represented by its signed fields, or Solana has no raw transaction, or
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
        case .evm(let request):
            task = makeEvmScanTask(request: request)
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

    private func makeEvmScanTask(request: EvmRequest) -> Task<BlockaidKeysignScanResult, Error> {
        Task { [rpcClient, logger] () throws -> BlockaidKeysignScanResult in
            let response = try await rpcClient.simulateEVMTransaction(
                chain: request.chain,
                from: request.from,
                to: request.to,
                amount: request.amount,
                data: request.data
            )
            Self.debugLog(response: response, logger: logger)
            let simulation = BlockaidSimulationParser.parse(
                response: response,
                chain: request.chain
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
            // The dApp keysign payload carries rawTransactions as base64 (see
            // SignSolana.rawTransactions); Blockaid's simulate endpoint expects
            // base58. Fail fast on any decode error rather than simulating on a
            // subset, which would make the hero show balance changes that don't
            // match what the user is signing.
            let rawTxsBase64 = keysignPayload.signSolana?.rawTransactions ?? []
            guard !rawTxsBase64.isEmpty else { return .empty }
            var rawTxsBase58: [String] = []
            rawTxsBase58.reserveCapacity(rawTxsBase64.count)
            for base64 in rawTxsBase64 {
                guard let data = Data(base64Encoded: base64) else {
                    logger.warning("solana scan aborted: rawTransaction base64 decode failed")
                    return .empty
                }
                rawTxsBase58.append(Base58.encodeNoCheck(data: data))
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

    private struct EvmRequest: Hashable {
        let chain: Chain
        let from: String
        let to: String
        let amount: String
        let data: String

        init?(payload: KeysignPayload) {
            guard BlockaidChainIdentifier.name(for: payload.coin.chain) != nil,
                  case .Ethereum = payload.chainSpecific,
                  payload.approvePayload == nil else { return nil }

            chain = payload.coin.chain
            from = payload.coin.address.lowercased()

            let target: String
            let rawAmount: BigInt
            let calldata: String
            switch payload.swapPayload {
            case .generic(let swap):
                // OneInchSwaps signs quote.tx, not the payload's transfer
                // fields. Never show a verdict for a different transaction.
                guard swap.fromCoin.chain == payload.coin.chain,
                      let value = BigInt(swap.quote.tx.value), value >= 0 else { return nil }
                target = swap.quote.tx.to
                rawAmount = value
                calldata = swap.quote.tx.data
            case .some:
                // Other swap signers may emit multiple or provider-specific
                // transactions that one EVM simulation cannot represent.
                return nil
            case .none:
                if payload.coin.isNativeToken {
                    target = payload.toAddress
                    rawAmount = payload.toAmount
                    calldata = payload.memo ?? "0x"
                } else {
                    // ERC20Helper signs `contractAddress.transfer(to, amount)`;
                    // the payload's toAddress/toAmount are token units, not an
                    // ETH value sent to the recipient.
                    guard let encoded = try? EthereumFunction.transferErc20Encoder(
                        address: payload.toAddress,
                        amount: payload.toAmount
                    ) else { return nil }
                    target = payload.coin.contractAddress
                    rawAmount = .zero
                    calldata = encoded
                }
            }

            guard rawAmount >= 0,
                  !target.isEmpty,
                  calldata.lowercased().hasPrefix("0x") else { return nil }
            let hex = calldata.dropFirst(2).lowercased()
            guard hex.count.isMultiple(of: 2),
                  hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) else {
                return nil
            }
            to = target.lowercased()
            amount = rawAmount.toEvenLengthHexString()
            data = "0x" + hex
        }
    }

    private enum CacheKey: Hashable {
        case evm(EvmRequest)
        case solana(transactionsDigest: String)

        init?(payload: KeysignPayload) {
            switch payload.coin.chainType {
            case .EVM:
                guard let request = EvmRequest(payload: payload) else { return nil }
                self = .evm(request)
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
