//
//  TokenCatalogRepository.swift
//  VultisigApp
//
//  Registry of `TokenCatalogProvider`s — the app-wide generalization of the
//  swap-only `DestinationTokenRegistry`. Providers register once at app startup
//  (see `VultisigApp.init`) and the repository aggregates their candidates.
//
//  Two configured shared instances of the one type keep the two surfaces
//  decoupled in phase 1:
//   - `shared`     — the swap destination picker's registry (SwapKit, THOR/Maya
//                    pool, secured). Consumed via `tokens(for:)` (per-provider
//                    buckets), byte-identical to the old `DestinationTokenRegistry`.
//   - `appCatalog` — the wallet token search / add-token catalog (bundled
//                    `TokensStore` + 1inch + Jupiter). Consumed via `catalog(for:)`.
//
//  Keyed by `kind`; re-registering the same kind overwrites in place (idempotent)
//  so a hot-reload or test override doesn't accumulate duplicates. Registration
//  order is preserved for deterministic output.
//

import Foundation

@MainActor
final class TokenCatalogRepository {
    /// Swap destination picker registry. Provider set unchanged from the former
    /// `DestinationTokenRegistry.shared`.
    static let shared = TokenCatalogRepository()

    /// App-wide token catalog for wallet search / add-token (and, transitively,
    /// the swap source picker via `TokenSearchService`).
    static let appCatalog = TokenCatalogRepository()

    private var providers: [any TokenCatalogProvider] = []

    /// Test-only — production uses the shared instances. Lets tests spin up an
    /// isolated registry without leaking state across cases.
    init() {}

    /// Register a provider. Idempotent on `kind` — re-registering the same kind
    /// overwrites the previous entry in place (preserving registration order).
    func register(_ provider: any TokenCatalogProvider) {
        if let existing = providers.firstIndex(where: { $0.kind == provider.kind }) {
            providers[existing] = provider
        } else {
            providers.append(provider)
        }
    }

    /// Per-provider destination-token buckets for `chain` — the swap destination
    /// picker's aggregation path. Preserves the exact former `DestinationTokenRegistry`
    /// semantics: one bucket per provider, in registration order, deduped by the
    /// picker (not here).
    ///
    /// Providers are awaited sequentially (the picker serialises on `MainActor`
    /// and the provider count is O(1-4)). Swap to a `TaskGroup` if that grows.
    func tokens(for chain: Chain, forceRefresh: Bool = false) async -> [DestinationTokenBucket] {
        var buckets: [DestinationTokenBucket] = []
        for provider in providers {
            let bucket = await provider.tokens(for: chain, forceRefresh: forceRefresh)
            buckets.append(bucket)
        }
        return buckets
    }

    /// The unified, deduped, precedence-merged, verification-carrying catalog for
    /// `chain`. Dedup is by `CoinMeta.uniqueId` (the app-wide key). On a
    /// collision the higher-`precedence` provider's `CoinMeta` wins (curated logo
    /// / priceProviderId survives) while the strongest `verification` seen is
    /// always kept. First-seen insertion order is preserved.
    ///
    /// Output is the *candidate* set — enable/disable stays `vault.coins`. Callers
    /// apply verification-to-surface (only `.curated`/`.verified` auto-appear).
    func catalog(for chain: Chain, forceRefresh: Bool = false) async -> [CatalogToken] {
        var order: [String] = []
        var winners: [String: CatalogToken] = [:]
        var winningPrecedence: [String: Int] = [:]

        for provider in providers {
            let precedence = provider.precedence
            let candidates = await provider.catalogTokens(for: chain, forceRefresh: forceRefresh)
            for candidate in candidates {
                // Defensive: a provider must only emit tokens for the requested
                // chain. Drop any mismatch so a misbehaving / compromised provider
                // can't smuggle a token onto a chain it doesn't belong to.
                guard candidate.meta.chain == chain else { continue }
                let id = candidate.uniqueId
                guard let existing = winners[id] else {
                    winners[id] = candidate
                    winningPrecedence[id] = precedence
                    order.append(id)
                    continue
                }
                // Strongest verification is always kept, regardless of which
                // provider's CoinMeta wins.
                let mergedVerification = TokenVerification.stronger(existing.verification, candidate.verification)
                if precedence > (winningPrecedence[id] ?? Int.min) {
                    // Higher-precedence provider's CoinMeta (+ sourceKind) wins.
                    winners[id] = CatalogToken(
                        meta: candidate.meta,
                        verification: mergedVerification,
                        sourceKind: candidate.sourceKind
                    )
                    winningPrecedence[id] = precedence
                } else if mergedVerification != existing.verification {
                    // Keep the existing (higher/equal precedence) CoinMeta but
                    // upgrade its verification to the strongest seen.
                    winners[id] = CatalogToken(
                        meta: existing.meta,
                        verification: mergedVerification,
                        sourceKind: existing.sourceKind
                    )
                }
            }
        }
        return order.compactMap { winners[$0] }
    }

    /// Test-only — count of currently-registered providers.
    var registeredCountForTesting: Int { providers.count }
}

/// Back-compat alias — the swap destination picker + its tests refer to the
/// registry by this name. New code should use `TokenCatalogRepository`.
typealias DestinationTokenRegistry = TokenCatalogRepository
