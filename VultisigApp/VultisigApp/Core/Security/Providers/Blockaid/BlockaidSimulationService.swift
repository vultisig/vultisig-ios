//
//  BlockaidSimulationService.swift
//  VultisigApp
//

import Foundation
import BigInt
import OSLog

/// Fetches and caches Blockaid simulation results for the dApp signing hero.
///
/// A single simulation underpins the hero across the verify → sign → done
/// screens. Caching by `(chain, memo)` lets each screen resolve the same
/// balance-change without re-hitting Blockaid's API. Failures are not
/// cached so the next screen retries; null results (chain supported but no
/// balance change to report) are cached to avoid refetching.
actor BlockaidSimulationService {

    static let shared = BlockaidSimulationService(
        rpcClient: BlockaidRpcClient(httpClient: HTTPClient())
    )

    private let rpcClient: BlockaidRpcClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "blockaid-simulation")

    private var cache: [CacheKey: BlockaidSimulationInfo?] = [:]
    private var inflight: [CacheKey: Task<BlockaidSimulationInfo?, Error>] = [:]

    init(rpcClient: BlockaidRpcClientProtocol) {
        self.rpcClient = rpcClient
    }

    /// Fetches the simulation for the given payload, coalescing concurrent
    /// callers and caching successful results by `(chain, memo)`.
    ///
    /// Returns `nil` when the chain is unsupported, the payload isn't a
    /// contract call, the simulation fails, or Blockaid reports no balance
    /// changes.
    func simulate(keysignPayload: KeysignPayload) async -> BlockaidSimulationInfo? {
        guard let key = CacheKey(payload: keysignPayload) else { return nil }

//        if let cached = cache[key] { return cached }
//        if let pending = inflight[key] { return try? await pending.value }

        let task = Task { [rpcClient, logger] () throws -> BlockaidSimulationInfo? in
            let response = try await rpcClient.simulateEVMTransaction(
                chain: keysignPayload.coin.chain,
                from: keysignPayload.coin.address,
                to: keysignPayload.toAddress,
                amount: keysignPayload.toAmount.toEvenLengthHexString(),
                data: keysignPayload.memo ?? "0x"
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let json = try? encoder.encode(response),
               let jsonString = String(data: json, encoding: .utf8) {
                logger.debug("simulation response: \(jsonString, privacy: .public)")
            }
            return BlockaidSimulationParser.parse(
                response: response,
                chain: keysignPayload.coin.chain
            )
        }
        inflight[key] = task
        defer { inflight[key] = nil }

        do {
            let result = try await task.value
            cache[key] = result
            return result
        } catch {
            logger.error("simulation failed: \(error.localizedDescription)")
            return nil
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
