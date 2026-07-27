//
//  TokenSelectionViewModel.swift
//  VultisigApp
//

import SwiftUI

@MainActor
class TokenSelectionViewModel: ObservableObject {

    @Published var searchText: String = .empty
    @Published var tokens: [CoinMeta] = []
    @Published var selectedTokens: [CoinMeta] = []
    @Published var preExistTokens: [CoinMeta] = []
    @Published var searchedTokens: [CoinMeta] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?
    /// `CoinMeta.uniqueId → verification` for the loaded catalog, so the row
    /// views can badge each token. Anything not in the map (vault-held coins,
    /// curated presets) is treated as `.curated` (no badge).
    @Published var verificationByUniqueId: [String: TokenVerification] = [:]
    /// Opt-in reveal of `.unverified` search results, default OFF. Per-session:
    /// the view model is recreated each time the picker is presented, so the safe
    /// default re-arms rather than persisting a risky choice across sessions.
    @Published var showUnverified: Bool = false

    /// Auto-surfacing (curated / verified) externals — always in the search pool.
    private var verifiedExternal: [CoinMeta] = []
    /// Withheld `.unverified` externals — folded into the search pool only while
    /// `showUnverified` is on.
    private var unverifiedExternal: [CoinMeta] = []

    private var loadingTask: Task<Void, Never>?

    private let logic = TokenSelectionLogic.shared

    var showRetry: Bool {
        return logic.showRetry(error: error)
    }

    /// Whether the loaded catalog has any withheld unverified candidates — gates
    /// the "Show unverified" toggle's visibility (no toggle when there's nothing
    /// to reveal, e.g. chains with no unverified long-tail).
    var hasUnverifiedResults: Bool {
        !unverifiedExternal.isEmpty
    }

    /// Verification for a row — defaults to `.curated` (unbadged) for tokens the
    /// catalog didn't tag (held coins, curated `TokensStore` presets).
    func verification(for coin: CoinMeta) -> TokenVerification {
        verificationByUniqueId[coin.uniqueId] ?? .curated
    }

    func loadData(chain: Chain, vault: Vault) {
        // Cancel any existing loading task
        loadingTask?.cancel()

        // Reset error state
        error = nil

        // Load basic tokens immediately (synchronous)
        let hiddenTokens = vault.hiddenTokens
        let chainCoins = vault.coins(for: chain)
        selectedTokens = logic.selectedTokens(chainCoins: chainCoins, tokens: tokens)
        preExistTokens = logic.preExistingTokens(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)

        // Start async loading of external tokens
        loadingTask = Task { [weak self] in
            guard let self else { return }
            await self.loadExternalTokens(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)
        }
    }

    func cancelLoading() {
        loadingTask?.cancel()
        isLoading = false
    }

    func updateSearchedTokens(chain: Chain, vault: Vault) {
        let chainCoins = vault.coins(for: chain)
        searchedTokens = logic.filteredTokens(chainCoins: chainCoins, searchText: searchText, tokens: tokens)
    }

    /// Flip the opt-in unverified reveal and re-derive the visible lists so the
    /// withheld candidates appear in (or disappear from) search immediately.
    func setShowUnverified(_ show: Bool, chain: Chain, vault: Vault) {
        guard show != showUnverified else { return }
        showUnverified = show
        recompute(chain: chain, chainCoins: vault.coins(for: chain), hiddenTokens: vault.hiddenTokens)
    }

    private func loadExternalTokens(chain: Chain, chainCoins: [Coin], hiddenTokens: [HiddenToken]) async {
        guard !Task.isCancelled else { return }

        isLoading = true
        error = nil

        do {
            let result = try await logic.loadExternalTokens(chain: chain)

            if !Task.isCancelled {
                verifiedExternal = result.verifiedTokens
                unverifiedExternal = result.unverifiedTokens
                verificationByUniqueId = result.verificationByUniqueId
                recompute(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)
            }
        } catch {
            // Capture the error for UI display
            self.error = error
        }

        isLoading = false
    }

    /// Re-derive the visible token pool and its dependent lists from the loaded
    /// externals under the current `showUnverified` setting. The unverified
    /// candidates only ever join the *search* pool (browse still shows held +
    /// curated presets, matching the pre-existing behaviour for verified
    /// externals too).
    private func recompute(chain: Chain, chainCoins: [Coin], hiddenTokens: [HiddenToken]) {
        tokens = TokenSelectionLogic.searchPool(
            verified: verifiedExternal,
            unverified: unverifiedExternal,
            showUnverified: showUnverified
        )
        selectedTokens = logic.selectedTokens(chainCoins: chainCoins, tokens: tokens)
        preExistTokens = logic.preExistingTokens(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)
        searchedTokens = logic.filteredTokens(chainCoins: chainCoins, searchText: searchText, tokens: tokens)
    }
}

// MARK: - TokenSelectionLogic

struct TokenSelectionLogic {
    static let shared = TokenSelectionLogic()

    private let searchService = TokenSearchService.shared

    private init() {}

    func selectedTokens(chainCoins: [Coin], tokens: [CoinMeta]) -> [CoinMeta] {
        let tickers = chainCoins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }

        let filteredTokens = tokens.filter { token in
            tickers.contains(token.ticker.lowercased())
        }
        // Convert tickers to tokens if they are not already in the existing tokens list
        let tickerTokens = chainCoins.filter { coin in
            tickers.contains(coin.ticker.lowercased()) &&
            !tokens.contains { token in token.ticker.lowercased() == coin.ticker.lowercased() }
        }.map { coin in
            coin.toCoinMeta()
        }

        return (filteredTokens + tickerTokens).uniqueBy { $0.uniqueId }
    }

    func preExistingTokens(chain: Chain, chainCoins: [Coin], hiddenTokens: [HiddenToken]) -> [CoinMeta] {
        let tickers = chainCoins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }

        return TokensStore.TokenSelectionAssets
            .filter { token in
                token.chain == chain &&
                !token.isNativeToken &&
                !tickers.contains(token.ticker.lowercased()) &&
                !hiddenTokens.contains { $0.matches(token) }
            }
    }

    func filteredTokens(chainCoins: [Coin], searchText: String, tokens: [CoinMeta]) -> [CoinMeta] {
        guard !searchText.isEmpty else {
            return []
        }

        let tickers = chainCoins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }

        let filtered = tokens
            .filter {
                $0.ticker.lowercased().contains(searchText.lowercased()) && !tickers.contains($0.ticker.lowercased()) }
            .prefix(20)

        return Array(filtered)
    }

    func showRetry(error: Error?) -> Bool {
        switch error {
        case let error as TokenSearchServiceError:
            return error == .networkError || error == .rateLimitExceeded
        default:
            return false
        }
    }

    /// The search token pool under the current toggle: the verified externals
    /// always, plus the withheld unverified ones only when the opt-in is on.
    /// Pure + `static` so the on/off gating is unit-tested directly.
    static func searchPool(verified: [CoinMeta], unverified: [CoinMeta], showUnverified: Bool) -> [CoinMeta] {
        verified + (showUnverified ? unverified : [])
    }

    struct LoadResult {
        /// Curated / verified externals (auto-surfacing).
        let verifiedTokens: [CoinMeta]
        /// Withheld `.unverified` externals (spam already filtered).
        let unverifiedTokens: [CoinMeta]
        /// `uniqueId → verification` for badging the rows.
        let verificationByUniqueId: [String: TokenVerification]
    }

    /// Fetches the verification-aware catalog for `chain`. The view model owns
    /// how the two lists are merged with the vault's held coins and how the
    /// unverified list is gated behind the toggle, so this stays a thin fetch.
    /// Errors propagate (retry UI) rather than being swallowed with `try?`.
    func loadExternalTokens(chain: Chain) async throws -> LoadResult {
        let catalog = try await searchService.loadCatalog(for: chain)
        return LoadResult(
            verifiedTokens: catalog.surfaceable,
            unverifiedTokens: catalog.unverified,
            verificationByUniqueId: catalog.verificationByUniqueId
        )
    }
}
