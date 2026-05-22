//
//  SwapKitTokensCache.swift
//  VultisigApp
//
//  Fans out `GET /tokens?provider=<NAME>` against the providers currently
//  enabled in the cached `/v3/providers` snapshot, dedupes by `identifier`,
//  buckets by reverse-mapped Vultisig `Chain`, and caches the result in
//  memory with a 24h TTL. The destination coin picker resolves SwapKit
//  destinations via `DestinationTokenRegistry`, which calls
//  `tokens(for: chain)` here.
//
//  Storage decision: in-memory only. SwapKit publishes a `timestamp` per
//  response and the list changes rarely; offline = no swap anyway, so
//  SwiftData persistence would buy nothing for the migration / Sendable
//  cost. See `wiki/.../swapkit-integration/tokens-picker-plan.md` §D2.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-tokens-cache")

@MainActor
final class SwapKitTokensCache: DestinationTokenProvider {
    static let shared = SwapKitTokensCache()

    let providerKind: String = "swapKit"

    private let httpClient: HTTPClientProtocol
    private let providerCache: SwapKitProviderCache
    private var snapshot: Snapshot?
    private var inFlight: Task<[Chain: DestinationTokenBucket]?, Never>?

    private struct Snapshot {
        let buckets: [Chain: DestinationTokenBucket]
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
    func tokens(for chain: Chain) async -> DestinationTokenBucket {
        await tokens(for: chain, now: Date())
    }

    /// Date-injectable variant used by tests / TTL-sensitive callers.
    func tokens(for chain: Chain, now: Date) async -> DestinationTokenBucket {
        guard SwapKitConfig.isFeatureEnabled else {
            return .empty(chain: chain)
        }
        let buckets = await ensureSnapshot(now: now)
        return buckets?[chain] ?? .empty(chain: chain)
    }

    /// Coalescing fetch — concurrent callers share one in-flight Task to
    /// avoid stampeding the proxy on first picker open. Returns the cached
    /// snapshot when fresh; otherwise refreshes.
    private func ensureSnapshot(now: Date) async -> [Chain: DestinationTokenBucket]? {
        if let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < SwapKitConfig.providerCacheTTL {
            return snapshot.buckets
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { [providerCache, httpClient] () -> [Chain: DestinationTokenBucket]? in
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
    func setSnapshot(buckets: [Chain: DestinationTokenBucket], fetchedAt: Date = Date()) {
        snapshot = Snapshot(buckets: buckets, fetchedAt: fetchedAt)
    }

    // MARK: - Fan-out + merge

    private static func fetchAll(
        providerCache: SwapKitProviderCache,
        httpClient: HTTPClientProtocol,
        now: Date
    ) async -> [Chain: DestinationTokenBucket]? {
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
    /// fixture data without standing up the cache + HTTPClient.
    /// `nonisolated` since the body touches no instance state and the
    /// inputs/outputs are value types — keeps test callers off MainActor.
    ///
    /// Dedup priority within a chain: a token already seen (by SwapKit
    /// `identifier`) wins over a later one. SwapKit responses are stable
    /// within a provider; cross-provider collisions are typically USDC
    /// variants where the first hit is correct. Insertion order of the
    /// resulting `tokens` array follows the order tokens were first
    /// observed across the merged responses.
    nonisolated static func mergeByChain(responses: [SwapKitTokensResponse]) -> [Chain: DestinationTokenBucket] {
        var byChainTokens: [Chain: [CoinMeta]] = [:]
        var byChainIdentifiers: [Chain: Set<String>] = [:]
        for response in responses {
            for token in response.tokens {
                guard let coinMeta = token.toCoinMeta() else { continue }
                let chain = coinMeta.chain
                var seen = byChainIdentifiers[chain] ?? []
                guard !seen.contains(token.identifier) else { continue }
                seen.insert(token.identifier)
                byChainIdentifiers[chain] = seen
                byChainTokens[chain, default: []].append(coinMeta)
            }
        }
        var buckets: [Chain: DestinationTokenBucket] = [:]
        for (chain, tokens) in byChainTokens {
            let uniqueIds = Set(tokens.map { $0.uniqueId })
            buckets[chain] = DestinationTokenBucket(
                chain: chain,
                tokens: tokens,
                uniqueIds: uniqueIds
            )
        }
        return buckets
    }
}
