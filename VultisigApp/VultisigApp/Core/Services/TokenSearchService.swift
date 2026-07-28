//
//  TokenSearchService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/08/2025.
//

import Foundation

struct TokenSearchService {
    static let shared = TokenSearchService()

    private init() {}

    /// The chain's token list for search / add-token, served from
    /// `SwapTokenListCache` when fresh (instant, no network) and refetched via
    /// `fetchUncached` otherwise. The cache is vault-independent — callers
    /// re-merge the vault's held coins themselves on each open.
    ///
    /// The list is now assembled by the app-wide `TokenCatalogRepository`
    /// (bundled curated `TokensStore` + 1inch + Jupiter, deduped by
    /// `CoinMeta.uniqueId` with the curated logo/priceProviderId winning). The
    /// caller-facing shape is unchanged — non-native `CoinMeta` for the chain.
    func loadTokens(for chain: Chain) async throws -> [CoinMeta] {
        try await SwapTokenListCache.shared.tokens(for: chain) {
            try await self.fetchUncached(for: chain)
        }
    }

    private func fetchUncached(for chain: Chain) async throws -> [CoinMeta] {
        guard !Task.isCancelled else { throw TokenSearchServiceError.cancelled }

        // The repository's providers fail open internally (bundled floor + disk
        // last-good), so `catalog(for:)` doesn't throw on a network miss — the
        // curated list is always at least available offline. Cancellation is
        // still surfaced so the picker's teardown supersedes the result.
        //
        // `appCatalog` is registered in `VultisigApp.init`, before any picker /
        // search UI can call this — so an empty result here is a genuinely empty
        // chain (e.g. a chain with no non-native curated tokens), never an
        // unconfigured registry.
        let candidates = await TokenCatalogRepository.appCatalog.catalog(for: chain)

        guard !Task.isCancelled else { throw TokenSearchServiceError.cancelled }

        return Self.surfaceableTokens(from: candidates)
    }

    /// The full verification-aware catalog for the wallet add-token picker: the
    /// auto-surfacing (curated / verified) list, the withheld `.unverified`
    /// candidates that search reveals (badged), and a `uniqueId →
    /// verification` map the row views badge from. Unlike `loadTokens`, this is
    /// NOT routed through `SwapTokenListCache` — that cache stays `[CoinMeta]`-typed
    /// and drives the swap pickers untouched; the wallet catalog is re-derived per
    /// screen open (the manage-tokens sheet isn't a rapid re-select surface, and
    /// the providers already fail-open to their disk snapshots offline).
    ///
    /// Threading the verification alongside the bare `[CoinMeta]` (rather than
    /// widening every list type to `[CatalogToken]`) is the least-invasive way to
    /// keep the swap picker's cache + merge paths unchanged.
    func loadCatalog(for chain: Chain) async throws -> TokenSearchResult {
        guard !Task.isCancelled else { throw TokenSearchServiceError.cancelled }

        let candidates = await TokenCatalogRepository.appCatalog.catalog(for: chain)

        guard !Task.isCancelled else { throw TokenSearchServiceError.cancelled }

        return Self.searchResult(from: candidates)
    }

    /// The verification-to-surface + non-native filter the search list applies to
    /// the catalog. Exposed `static` so the filter is exercised directly by tests
    /// (rather than a duplicated helper) and reused by any future catalog reader.
    ///
    /// Verification-to-surface: only curated / verified candidates auto-appear in
    /// the wallet add-token search + the swap source browse list. Unverified
    /// candidates (long-tail 1inch tokens with no CoinGecko listing, lookalike
    /// USDC/USDT on a different contract, airdrop dust) are withheld — they stay
    /// addable through the explicit custom-token (paste-contract) flow, matching
    /// the MetaMask/Rabby "verified auto, unknown via manual import" posture. The
    /// enabled set (`vault.coins`) is untouched. Native tokens are added to the
    /// picker separately and aren't addable in the wallet flow, so drop them too.
    static func surfaceableTokens(from candidates: [CatalogToken]) -> [CoinMeta] {
        candidates
            .filter { $0.autoSurfaces }
            .filter { !$0.meta.isNativeToken }
            .map { $0.meta }
    }

    /// Splits the catalog into the wallet picker's three verification-aware
    /// outputs. `surfaceable` is the auto-surfacing (curated / verified,
    /// non-native) list; `unverified` is the withheld long-tail search reveals.
    /// The synchronous `isLikelySpam` hard gate is applied to
    /// BOTH — spam never surfaces, verified or unverified, browse or search (the
    /// dynamic-catalog risk posture). It's applied here in the wallet catalog
    /// path only: the swap-shared `surfaceableTokens`/`loadTokens` path is left
    /// untouched so the swap pickers don't regress. `verificationByUniqueId`
    /// lets the row views badge each token without reaching back into the
    /// repository.
    static func searchResult(from candidates: [CatalogToken]) -> TokenSearchResult {
        let safe = candidates
            .filter { !$0.meta.isNativeToken }
            .filter { !CoinService.isLikelySpam($0.meta) }

        let surfaceable = safe.filter { $0.autoSurfaces }.map { $0.meta }
        let unverified = safe.filter { !$0.autoSurfaces }.map { $0.meta }

        var verificationByUniqueId: [String: TokenVerification] = [:]
        for candidate in safe {
            verificationByUniqueId[candidate.uniqueId] = candidate.verification
        }

        return TokenSearchResult(
            surfaceable: surfaceable,
            unverified: unverified,
            verificationByUniqueId: verificationByUniqueId
        )
    }
}

/// The wallet add-token picker's verification-aware view of the catalog. Kept a
/// value type so it crosses the actor boundary cleanly.
struct TokenSearchResult {
    /// Curated / verified, non-native — the tokens that auto-surface (default).
    let surfaceable: [CoinMeta]
    /// Withheld `.unverified` candidates (non-native, spam-filtered) that
    /// search reveals.
    let unverified: [CoinMeta]
    /// `CoinMeta.uniqueId → verification` for badging. Only non-native entries.
    let verificationByUniqueId: [String: TokenVerification]
}

/// Cancellation is the only failure this service can report: the catalog's
/// providers fail open internally (bundled curated floor + last-good disk
/// snapshot), so a network outage or a rate-limited provider degrades the list
/// rather than throwing.
enum TokenSearchServiceError: Error, LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Request cancelled"
        }
    }
}
