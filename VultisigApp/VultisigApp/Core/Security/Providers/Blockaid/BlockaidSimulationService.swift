//
//  BlockaidSimulationService.swift
//  VultisigApp
//

import Foundation
import OSLog

/// Combined output of a Blockaid `/evm/json-rpc/scan` call for a keysign
/// payload: the parsed balance-change simulation plus the risk validation
/// result that drives the `SecurityScannerHeaderView` above the hero.
struct BlockaidKeysignScanResult: Equatable {
    let simulation: BlockaidSimulationInfo?
    let scannerResult: SecurityScannerResult?

    static let empty = BlockaidKeysignScanResult(simulation: nil, scannerResult: nil)
}

/// Fetches and caches Blockaid scan results for the dApp signing hero.
///
/// A single scan underpins both the balance-change hero and the
/// "Scanned by Blockaid" header across the verify → sign → done screens.
/// Caching by `(chain, memo)` lets each screen resolve the same data without
/// re-hitting Blockaid's API. Failures are not cached so the next screen
/// retries; empty results (chain supported but no balance change or risk to
/// report) are cached to avoid refetching.
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
    /// callers and caching successful results by `(chain, memo)`.
    ///
    /// Returns `.empty` when the chain is unsupported, the payload isn't a
    /// contract call, or the scan fails.
    func scan(keysignPayload: KeysignPayload) async -> BlockaidKeysignScanResult {
        guard let key = CacheKey(payload: keysignPayload) else { return .empty }

        if let cached = cache[key] { return cached }
        if let pending = inflight[key] { return (try? await pending.value) ?? .empty }

        let task = Task { [rpcClient, logger] () throws -> BlockaidKeysignScanResult in
            let response = try await rpcClient.simulateEVMTransaction(
                chain: keysignPayload.coin.chain,
                from: keysignPayload.coin.address,
                to: keysignPayload.toAddress,
                amount: keysignPayload.toAmount.toEvenLengthHexString(),
                data: keysignPayload.memo ?? "0x"
            )
            #if DEBUG
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let json = try? encoder.encode(response),
               let jsonString = String(data: json, encoding: .utf8) {
                logger.debug("scan response: \(jsonString, privacy: .public)")
            }
            #endif
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

    // MARK: - Cache Key

    private struct CacheKey: Hashable {
        let chain: Chain
        let memo: String

        init?(payload: KeysignPayload) {
            guard payload.coin.chainType == .EVM else { return nil }
            guard let memo = payload.memo?.lowercased(),
                  memo.hasPrefix("0x"),
                  memo.count > 2 else { return nil }
            self.chain = payload.coin.chain
            self.memo = memo
        }
    }
}
