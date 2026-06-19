//
//  NativePoolEligibilityCache.swift
//  VultisigApp
//
//  Caches each native protocol's live `Available` swap pools behind a TTL and
//  derives the dynamic swap-asset eligibility set. Modeled on
//  `SwapKitProviderCache`: an actor, one snapshot per protocol, fail-open with
//  last-good fallback, a `nonisolated static` synchronous predicate, and a
//  `setSnapshot` test seam.
//

import Foundation
import OSLog

actor NativePoolEligibilityCache {
    static let shared = NativePoolEligibilityCache()

    private let httpClient: HTTPClientProtocol
    private var thorSnapshot: NativePoolSnapshot?
    private var mayaSnapshot: NativePoolSnapshot?
    private let cacheTTL: TimeInterval = 5 * 60
    private let logger = Logger(subsystem: "com.vultisig.app", category: "native-pool-eligibility")

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Refresh-or-cached `Available` pools for a protocol. Fail-open with
    /// last-good (mirrors `SwapKitProviderCache.providers`): returns the prior
    /// snapshot on a fetch failure, or `nil` when there is neither a fresh fetch
    /// nor a prior snapshot — callers then consult only the static fallback.
    func pools(_ proto: NativeSwapProtocol, now: Date = Date()) async -> [NativePoolAsset]? {
        if let snapshot = snapshot(for: proto), now.timeIntervalSince(snapshot.fetchedAt) < cacheTTL {
            return snapshot.pools
        }
        do {
            let pools = try await fetchPools(proto)
            let fresh = NativePoolSnapshot(pools: pools, fetchedAt: now)
            store(fresh, for: proto)
            return fresh.pools
        } catch {
            logger.warning("native pool fetch failed: \(error.localizedDescription, privacy: .public)")
            return snapshot(for: proto)?.pools
        }
    }

    /// Replace a protocol's snapshot — test seam so tests don't stand up a fake
    /// HTTPClient.
    func setSnapshot(_ proto: NativeSwapProtocol, _ snapshot: NativePoolSnapshot) {
        store(snapshot, for: proto)
    }

    // MARK: - Private

    private func snapshot(for proto: NativeSwapProtocol) -> NativePoolSnapshot? {
        switch proto {
        case .thorchain: return thorSnapshot
        case .mayachain: return mayaSnapshot
        }
    }

    private func store(_ snapshot: NativePoolSnapshot, for proto: NativeSwapProtocol) {
        switch proto {
        case .thorchain: thorSnapshot = snapshot
        case .mayachain: mayaSnapshot = snapshot
        }
    }

    /// Fetch + normalize a protocol's pools, keeping only `Available` ones.
    private func fetchPools(_ proto: NativeSwapProtocol) async throws -> [NativePoolAsset] {
        switch proto {
        case .thorchain:
            let response = try await httpClient.request(
                ThorchainMainnetAPI(.pools),
                responseType: [THORChainPoolResponse].self
            )
            return response.data.compactMap {
                NativePoolAsset.parse(assetId: $0.asset, status: $0.status, tradingHalted: $0.tradingHalted)
            }.filter { $0.isAvailable }
        case .mayachain:
            let response = try await httpClient.request(
                MayaChainAPI(.pools),
                responseType: [MayaPoolResponse].self
            )
            return response.data.compactMap {
                NativePoolAsset.parse(assetId: $0.asset, status: $0.status, tradingHalted: false)
            }.filter { $0.isAvailable }
        }
    }
}
