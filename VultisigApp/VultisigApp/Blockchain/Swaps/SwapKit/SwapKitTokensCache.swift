//
//  SwapKitTokensCache.swift
//  VultisigApp
//
//  Fans out `GET /tokens?provider=<NAME>` against the providers currently
//  enabled in the cached `/v3/providers` snapshot, dedupes by `identifier`,
//  buckets by reverse-mapped Vultisig `Chain`, and caches the result in
//  memory with a 24h TTL. The destination coin picker calls
//  `tokens(for: chain)` to surface SwapKit destinations beyond the existing
//  curated + 1inch + Jupiter lists.
//
//  Storage decision: in-memory only. SwapKit publishes a `timestamp` per
//  response and the list changes rarely; offline = no swap anyway, so
//  SwiftData persistence would buy nothing for the migration / Sendable
//  cost. See `wiki/.../swapkit-integration/tokens-picker-plan.md` §D2.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-tokens-cache")

/// Single bucket inside the cache — tokens for one Vultisig `Chain`, indexed
/// by SwapKit identifier so the picker's "is this a SwapKit-only token?"
/// predicate is O(1).
struct SwapKitTokensBucket {
    let chain: Chain
    /// `identifier` (e.g. `"ETH.USDT-0xdAC17F..."`) -> adapted CoinMeta.
    let byIdentifier: [String: CoinMeta]
    /// Lowercased `CoinMeta.uniqueId` set — used by the picker to detect
    /// "SwapKit unlocks this token" overlap against the existing curated +
    /// 1inch + Jupiter union.
    let uniqueIds: Set<String>

    var tokens: [CoinMeta] { Array(byIdentifier.values) }
}

actor SwapKitTokensCache {
    static let shared = SwapKitTokensCache()

    private let httpClient: HTTPClientProtocol
    private let providerCache: SwapKitProviderCache
    private var snapshot: Snapshot?
    private var inFlight: Task<[Chain: SwapKitTokensBucket]?, Never>?

    private struct Snapshot {
        let buckets: [Chain: SwapKitTokensBucket]
        let fetchedAt: Date
    }

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        providerCache: SwapKitProviderCache = .shared
    ) {
        self.httpClient = httpClient
        self.providerCache = providerCache
    }

    /// Tokens unlocked by SwapKit on `chain`, fetched + cached on first call.
    /// Returns an empty bucket (rather than nil) when:
    ///  - The feature flag is OFF (defensive — callers should already gate
    ///    on `SwapKitConfig.isFeatureEnabled`, but the cache fails closed).
    ///  - The cache fetch fails entirely and we have no prior snapshot.
    ///  - SwapKit has no tokens on this chain (cache built, bucket missing).
    /// The picker treats "empty bucket" identically to "no SwapKit unlock"
    /// and falls back to the curated + 1inch + Jupiter list it has today.
    func tokens(for chain: Chain, now: Date = Date()) async -> SwapKitTokensBucket {
        guard SwapKitConfig.isFeatureEnabled else {
            return SwapKitTokensBucket(chain: chain, byIdentifier: [:], uniqueIds: [])
        }
        let buckets = await ensureSnapshot(now: now)
        return buckets?[chain] ?? SwapKitTokensBucket(chain: chain, byIdentifier: [:], uniqueIds: [])
    }

    /// Coalescing fetch — concurrent callers share one in-flight Task to
    /// avoid stampeding the proxy on first picker open. Returns the cached
    /// snapshot when fresh; otherwise refreshes.
    private func ensureSnapshot(now: Date) async -> [Chain: SwapKitTokensBucket]? {
        if let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < SwapKitConfig.providerCacheTTL {
            return snapshot.buckets
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { [providerCache, httpClient] () -> [Chain: SwapKitTokensBucket]? in
            await Self.fetchAll(providerCache: providerCache, httpClient: httpClient, now: now)
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if let result {
            snapshot = Snapshot(buckets: result, fetchedAt: now)
        }
        return result ?? snapshot?.buckets
    }

    /// Replace the snapshot — exposed for tests so they don't need a fake
    /// `HTTPClient`. Mirrors the affordance `SwapKitProviderCache.setSnapshot`
    /// gives provider-cache tests.
    func setSnapshot(buckets: [Chain: SwapKitTokensBucket], fetchedAt: Date = Date()) {
        snapshot = Snapshot(buckets: buckets, fetchedAt: fetchedAt)
    }

    // MARK: - Fan-out + merge

    private static func fetchAll(
        providerCache: SwapKitProviderCache,
        httpClient: HTTPClientProtocol,
        now: Date
    ) async -> [Chain: SwapKitTokensBucket]? {
        guard let allProviders = await providerCache.providers(now: now) else {
            logger.info("[swapkit-tokens] no provider snapshot available — skipping fetch")
            return nil
        }
        let providerNames = allProviders
            .map { $0.name.uppercased() }
            .filter { !SwapKitConfig.filteredProviders.contains($0) }

        guard !providerNames.isEmpty else {
            logger.info("[swapkit-tokens] no eligible providers after THORChain/Maya filter")
            return [:]
        }

        let fetched: [SwapKitTokensResponse] = await withTaskGroup(of: SwapKitTokensResponse?.self) { group in
            for name in providerNames {
                group.addTask {
                    await fetchTokens(provider: name, httpClient: httpClient)
                }
            }
            var collected: [SwapKitTokensResponse] = []
            for await response in group {
                if let response { collected.append(response) }
            }
            return collected
        }

        return mergeByChain(responses: fetched)
    }

    private static func fetchTokens(
        provider: String,
        httpClient: HTTPClientProtocol
    ) async -> SwapKitTokensResponse? {
        do {
            let response = try await httpClient.request(
                SwapKitAPI.tokens(provider: provider),
                responseType: SwapKitTokensResponse.self
            )
            return response.data
        } catch {
            logger.warning("[swapkit-tokens] failed to fetch \(provider, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Dedup + bucket. Exposed as a static so tests can drive it from
    /// fixture data without standing up the actor + HTTPClient.
    static func mergeByChain(responses: [SwapKitTokensResponse]) -> [Chain: SwapKitTokensBucket] {
        var byChain: [Chain: [String: CoinMeta]] = [:]
        // Dedup priority: a token already seen (by identifier) on a given
        // chain wins over a later one. SwapKit responses are stable within
        // a provider; cross-provider collisions are USDC variants where the
        // first hit is correct.
        for response in responses {
            for token in response.tokens {
                guard let coinMeta = token.toCoinMeta() else { continue }
                let chain = coinMeta.chain
                if byChain[chain] == nil { byChain[chain] = [:] }
                if byChain[chain]?[token.identifier] == nil {
                    byChain[chain]?[token.identifier] = coinMeta
                }
            }
        }
        var buckets: [Chain: SwapKitTokensBucket] = [:]
        for (chain, byIdentifier) in byChain {
            let uniqueIds = Set(byIdentifier.values.map { $0.uniqueId })
            buckets[chain] = SwapKitTokensBucket(
                chain: chain,
                byIdentifier: byIdentifier,
                uniqueIds: uniqueIds
            )
        }
        return buckets
    }
}
