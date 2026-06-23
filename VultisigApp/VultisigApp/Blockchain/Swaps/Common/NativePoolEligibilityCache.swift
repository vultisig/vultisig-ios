//
//  NativePoolEligibilityCache.swift
//  VultisigApp
//
//  Caches each native protocol's live `Available` swap pools behind a TTL and
//  derives the dynamic swap-asset eligibility set. A thin wrapper over the
//  shared `TTLCache` (one snapshot per protocol, fail-open with last-good
//  fallback, injectable `now`, `setSnapshot` test seam).
//

import Foundation
import OSLog

actor NativePoolEligibilityCache {
    static let shared = NativePoolEligibilityCache()

    private let httpClient: HTTPClientProtocol
    private let cache = TTLCache<NativeSwapProtocol, [NativePoolAsset]>()
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
        do {
            return try await cache.value(for: proto, now: now, ttl: cacheTTL) { [httpClient] in
                try await Self.fetchPools(proto, httpClient: httpClient)
            }
        } catch {
            logger.warning("native pool fetch failed: \(error.localizedDescription, privacy: .public)")
            return await cache.peek(proto)
        }
    }

    /// Replace a protocol's snapshot — test seam so tests don't stand up a fake
    /// HTTPClient.
    func setSnapshot(_ proto: NativeSwapProtocol, _ snapshot: NativePoolSnapshot) async {
        await cache.setCached(snapshot.pools, for: proto, fetchedAt: snapshot.fetchedAt)
    }

    // MARK: - Private

    /// Fetch + normalize a protocol's pools, keeping only `Available` ones.
    private static func fetchPools(_ proto: NativeSwapProtocol, httpClient: HTTPClientProtocol) async throws -> [NativePoolAsset] {
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
