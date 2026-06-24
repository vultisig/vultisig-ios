//
//  DestinationTokenProvider.swift
//  VultisigApp
//
//  Provider-agnostic contract for destination-side coin-picker sources.
//  Each concrete conformer owns its own fetch / cache / feature-flag
//  lifecycle and returns the slice of tokens it can deliver to on a
//  given `Chain`. The picker aggregates buckets from every registered
//  provider via `DestinationTokenRegistry` and dedupes by
//  `CoinMeta.uniqueId`.
//
//  Today only `SwapKitTokensCache` conforms; future destination-token
//  sources (additional aggregators, allowlist services, etc.) plug in
//  without touching the picker.
//

import Foundation

@MainActor
protocol DestinationTokenProvider: AnyObject {
    /// Discriminator for logging / debugging only. The picker dedups by
    /// `CoinMeta.uniqueId`, so colliding providerKinds don't break
    /// behaviour. Used as the registry key — re-registering the same
    /// kind overwrites the previous entry.
    var providerKind: String { get }

    /// Tokens this provider can deliver to on `chain`. Empty bucket when
    /// the provider is disabled, doesn't support the chain, or its data
    /// isn't yet warmed. Concrete conformers short-circuit on feature
    /// flags / catalog absence as appropriate.
    ///
    /// `forceRefresh` asks the provider to bypass its freshness/TTL early-return
    /// and re-fetch its catalog, while still coalescing concurrent callers and
    /// serving last-good on failure. The picker passes `true` only on its first
    /// open per presentation so users see an up-to-date catalog; in-session
    /// re-merges (search debounce, chain re-select) pass `false` to stay
    /// instant/offline. Providers without a refreshable catalog ignore it.
    func tokens(for chain: Chain, forceRefresh: Bool) async -> DestinationTokenBucket
}

extension DestinationTokenProvider {
    func tokens(for chain: Chain) async -> DestinationTokenBucket {
        await tokens(for: chain, forceRefresh: false)
    }
}
