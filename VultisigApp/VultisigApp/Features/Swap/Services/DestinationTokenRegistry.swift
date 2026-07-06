//
//  DestinationTokenRegistry.swift
//  VultisigApp
//
//  Registry of `DestinationTokenProvider` conformers. The destination
//  coin picker (`SwapCoinSelectionLogic`) walks every registered
//  provider to assemble the destination-token list — providers slot in
//  at app startup without the picker knowing about any of them.
//
//  Keyed by `providerKind`. Re-registering the same kind overwrites the
//  previous entry (idempotent) so a hot-reload during development or a
//  test-only override doesn't accumulate duplicates. Registration order
//  is preserved so `tokens(for:)` returns buckets in a deterministic
//  sequence (the picker's merge depends only on dedup-by-uniqueId, but
//  deterministic order keeps tests stable).
//

import Foundation

@MainActor
final class DestinationTokenRegistry {
    static let shared = DestinationTokenRegistry()

    private var providers: [any DestinationTokenProvider] = []

    /// Test-only — production uses `shared`. Allows tests to spin up an
    /// isolated registry without leaking state into other test cases.
    init() {}

    /// Register a provider. Idempotent on `providerKind` — re-registering
    /// the same kind overwrites the previous entry in place (preserving
    /// its registration order). Called once per conformer at app
    /// startup.
    func register(_ provider: any DestinationTokenProvider) {
        if let existing = providers.firstIndex(where: { $0.providerKind == provider.providerKind }) {
            providers[existing] = provider
        } else {
            providers.append(provider)
        }
    }

    /// Aggregate destination tokens from every registered provider for
    /// `chain`. `forceRefresh` is forwarded to each provider so the picker's
    /// first open per presentation can re-fetch catalogs while in-session
    /// re-merges stay on cached data.
    ///
    /// Concurrency: providers are awaited sequentially — the picker
    /// already serialises on `MainActor`, and the registered-provider
    /// count is O(1-3) today. If that changes, swap to a `TaskGroup`.
    func tokens(for chain: Chain, forceRefresh: Bool = false) async -> [DestinationTokenBucket] {
        var buckets: [DestinationTokenBucket] = []
        for provider in providers {
            let bucket = await provider.tokens(for: chain, forceRefresh: forceRefresh)
            buckets.append(bucket)
        }
        return buckets
    }

    /// Test-only — drop every registered provider so test cases start
    /// clean.
    func removeAllForTesting() {
        providers.removeAll()
    }

    /// Test-only — count of currently-registered providers.
    var registeredCountForTesting: Int { providers.count }
}
