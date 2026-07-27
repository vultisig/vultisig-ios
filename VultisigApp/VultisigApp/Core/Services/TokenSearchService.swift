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
}

enum TokenSearchServiceError: Error, LocalizedError {
    case noTokens
    case networkError
    case rateLimitExceeded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noTokens:
            return "Tokens not found"
        case .networkError:
            return "Unable to connect.\nPlease check your internet connection and try again"
        case .rateLimitExceeded:
            return "Too many requests.\nPlease close this screen and try again later"
        case .cancelled:
            return "Request cancelled"
        }
    }
}
