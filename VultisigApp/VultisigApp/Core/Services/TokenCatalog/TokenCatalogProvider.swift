//
//  TokenCatalogProvider.swift
//  VultisigApp
//
//  App-wide, provider-agnostic contract for token-catalog sources. Generalizes
//  the swap-only `DestinationTokenProvider`: the static `TokensStore` and every
//  dynamic source (1inch, Jupiter, SwapKit, native pools, secured assets) all
//  conform, so token search / pickers / discovery can pull from one registry.
//
//  Each concrete conformer owns its own fetch / cache / feature-flag lifecycle
//  and returns the slice of tokens it can deliver on a given `Chain`. The
//  `DestinationTokenProvider` / `DestinationTokenRegistry` names remain as
//  typealiases so the swap destination picker compiles unchanged.
//
//  The bucket method (`tokens(for:)`) stays the primitive so the swap picker's
//  merge and every existing provider/test keep working untouched. Trust-tagged
//  candidates (`catalogTokens(for:)`) are derived on top: by default every token
//  a provider emits gets the provider's `verification`; a provider with
//  per-token trust (1inch CoinGecko-verified vs not) overrides `catalogTokens`.
//

import Foundation

@MainActor
protocol TokenCatalogProvider: AnyObject {
    /// Discriminator for the registry key + logging. Re-registering the same
    /// kind overwrites the previous entry (idempotent). Dedup is by
    /// `CoinMeta.uniqueId`, so colliding kinds don't break behaviour.
    var kind: String { get }

    /// Dedup winner on a `uniqueId` collision across providers: the higher
    /// `precedence` provider's `CoinMeta` is kept (so a curated logo /
    /// priceProviderId survives), while the strongest `verification` seen is
    /// always retained. Default `0`.
    var precedence: Int { get }

    /// Verification applied to every token this provider emits, unless the
    /// provider overrides `catalogTokens(for:forceRefresh:)` for per-token
    /// trust. Default `.unverified` (fail-closed).
    var verification: TokenVerification { get }

    /// Tokens this provider can deliver on `chain`. Empty bucket when the
    /// provider is disabled, doesn't support the chain, or its data isn't warmed.
    ///
    /// `forceRefresh` asks the provider to bypass its freshness/TTL early-return
    /// and re-fetch, while still coalescing concurrent callers and serving
    /// last-good on failure. Providers without a refreshable catalog ignore it.
    func tokens(for chain: Chain, forceRefresh: Bool) async -> DestinationTokenBucket

    /// Trust-tagged candidates for `chain`. Default derives from `tokens(for:)`,
    /// tagging every token with `verification`; providers with per-token trust
    /// override this.
    func catalogTokens(for chain: Chain, forceRefresh: Bool) async -> [CatalogToken]
}

extension TokenCatalogProvider {
    var precedence: Int { 0 }
    var verification: TokenVerification { .unverified }

    func tokens(for chain: Chain) async -> DestinationTokenBucket {
        await tokens(for: chain, forceRefresh: false)
    }

    func catalogTokens(for chain: Chain, forceRefresh: Bool) async -> [CatalogToken] {
        let bucket = await tokens(for: chain, forceRefresh: forceRefresh)
        let providerVerification = verification
        let providerKind = kind
        return bucket.tokens.map {
            CatalogToken(meta: $0, verification: providerVerification, sourceKind: providerKind)
        }
    }

    func catalogTokens(for chain: Chain) async -> [CatalogToken] {
        await catalogTokens(for: chain, forceRefresh: false)
    }
}

/// Back-compat alias — the swap destination picker + its tests refer to the
/// provider contract by this name. New code should use `TokenCatalogProvider`.
typealias DestinationTokenProvider = TokenCatalogProvider
