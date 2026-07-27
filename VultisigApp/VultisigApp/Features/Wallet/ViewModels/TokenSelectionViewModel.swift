//
//  TokenSelectionViewModel.swift
//  VultisigApp
//

import SwiftUI

@MainActor
class TokenSelectionViewModel: ObservableObject {

    @Published var searchText: String = .empty
    /// Held non-native coins for the chain (browse, shown first).
    @Published var selectedTokens: [CoinMeta] = []
    /// Curated `TokensStore` presets not held/hidden (browse, after held). Always
    /// present synchronously — independent of the async provider fetch.
    @Published var preExistTokens: [CoinMeta] = []
    /// Verified provider breadth for browse (1inch CoinGecko / Jupiter), deduped
    /// against the local tokens above. Empty until the provider fetch lands.
    @Published var browseProviderTokens: [CoinMeta] = []
    /// Search results over the full local-first pool (local + verified +
    /// unverified). Unverified rows carry the ⚠ badge — typing is what reveals
    /// the unverified long-tail.
    @Published var searchedTokens: [CoinMeta] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?
    /// `CoinMeta.uniqueId → verification` for the loaded catalog, so the row
    /// views can badge each token. Anything not in the map (vault-held coins,
    /// curated presets) is treated as `.curated` (no badge).
    @Published var verificationByUniqueId: [String: TokenVerification] = [:]

    /// Raw vault-independent catalog results, kept so a search-text change or a
    /// provider outcome re-derives without refetching. Empty until (or if) the
    /// fetch lands — the local presets/held always render regardless.
    private var catalogSurfaceable: [CoinMeta] = []
    private var catalogUnverified: [CoinMeta] = []
    /// The full local-first search pool (curated presets + verified + unverified),
    /// filtered by the query into `searchedTokens`. Always contains the presets
    /// so a curated/local token stays searchable even when the provider fetch
    /// is pending or fails.
    private var searchableTokens: [CoinMeta] = []

    private var loadingTask: Task<Void, Never>?

    private let logic = TokenSelectionLogic.shared
    private let loadCatalog: (Chain) async throws -> TokenSearchResult

    /// `loadCatalog` is injectable so tests can drive the provider outcome
    /// (including a throw) without the network. Production uses the shared
    /// `TokenSearchService`.
    init(loadCatalog: @escaping (Chain) async throws -> TokenSearchResult = { try await TokenSearchService.shared.loadCatalog(for: $0) }) {
        self.loadCatalog = loadCatalog
    }

    var showRetry: Bool {
        return logic.showRetry(error: error)
    }

    /// Verification for a row — defaults to `.curated` (unbadged) for tokens the
    /// catalog didn't tag (held coins, curated `TokensStore` presets).
    func verification(for coin: CoinMeta) -> TokenVerification {
        verificationByUniqueId[coin.uniqueId] ?? .curated
    }

    func loadData(chain: Chain, vault: Vault) {
        loadingTask?.cancel()
        loadingTask = Task { [weak self] in
            await self?.load(chain: chain, vault: vault)
        }
    }

    /// Awaitable load — the local pool renders synchronously first (so browse +
    /// search work before any network), then the provider breadth is folded in.
    /// Exposed so tests can await a deterministic load with an injected catalog.
    func load(chain: Chain, vault: Vault) async {
        error = nil

        let hiddenTokens = vault.hiddenTokens
        let chainCoins = vault.coins(for: chain)

        // Local-first, synchronous: held + curated presets are always present
        // and searchable, independent of the async provider fetch.
        recompute(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)

        await loadExternalTokens(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)
    }

    func cancelLoading() {
        loadingTask?.cancel()
        isLoading = false
    }

    func updateSearchedTokens(chain: Chain, vault: Vault) {
        let chainCoins = vault.coins(for: chain)
        searchedTokens = logic.filteredTokens(chainCoins: chainCoins, searchText: searchText, tokens: searchableTokens)
    }

    private func loadExternalTokens(chain: Chain, chainCoins: [Coin], hiddenTokens: [HiddenToken]) async {
        guard !Task.isCancelled else { return }

        isLoading = true
        error = nil

        do {
            let result = try await loadCatalog(chain)
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            catalogSurfaceable = result.surfaceable
            catalogUnverified = result.unverified
            verificationByUniqueId = result.verificationByUniqueId
        } catch {
            // Fail open: keep the local presets/held (already rendered) fully
            // searchable rather than blanking the list. Surface the error for the
            // retry affordance but still re-derive from what's local below.
            self.error = error
        }

        if !Task.isCancelled {
            recompute(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)
        }
        isLoading = false
    }

    /// Re-derive every visible list from the local presets/held + the current
    /// (possibly empty) catalog. Ordering is local-first everywhere: held, then
    /// curated presets, then provider breadth (deduped by `uniqueId`). Browse
    /// shows curated/local + verified; search adds the badged unverified long-tail.
    private func recompute(chain: Chain, chainCoins: [Coin], hiddenTokens: [HiddenToken]) {
        // Enrich held coins with catalog metadata where available.
        let catalogMetas = catalogSurfaceable + catalogUnverified
        selectedTokens = logic.selectedTokens(chainCoins: chainCoins, tokens: catalogMetas)
        preExistTokens = logic.preExistingTokens(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)

        let localIds = Set((selectedTokens + preExistTokens).map { $0.uniqueId })
        // Provider verified breadth (curated overlaps are already local): drop
        // anything local or user-hidden.
        let verifiedBreadth = logic.providerTokens(catalogSurfaceable, excludingLocal: localIds, hiddenTokens: hiddenTokens)
        let verifiedIds = localIds.union(verifiedBreadth.map { $0.uniqueId })
        let unverifiedBreadth = logic.providerTokens(catalogUnverified, excludingLocal: verifiedIds, hiddenTokens: hiddenTokens)

        browseProviderTokens = verifiedBreadth
        searchableTokens = TokenSelectionLogic.mergeLocalFirst([preExistTokens, verifiedBreadth, unverifiedBreadth])
        searchedTokens = logic.filteredTokens(chainCoins: chainCoins, searchText: searchText, tokens: searchableTokens)
    }
}

// MARK: - TokenSelectionLogic

struct TokenSelectionLogic {
    static let shared = TokenSelectionLogic()

    private init() {}

    /// The vault's held non-native coins for browse, enriched with catalog
    /// metadata (logo / priceProviderId) when the catalog carries the SAME token.
    ///
    /// Matching is by `uniqueId` (chain + ticker + contract), never by ticker
    /// alone: a ticker match would let an unverified lookalike sharing a held
    /// ticker (e.g. a fake `USDC` on a different contract) ride into the held set
    /// and auto-surface in browse. Each held coin yields exactly one row — the
    /// catalog meta when present, else the coin's own meta.
    func selectedTokens(chainCoins: [Coin], tokens: [CoinMeta]) -> [CoinMeta] {
        let catalogByUniqueId = Dictionary(
            tokens.map { ($0.uniqueId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return chainCoins
            .filter { !$0.isNativeToken }
            .map { coin in
                let coinMeta = coin.toCoinMeta()
                return catalogByUniqueId[coinMeta.uniqueId] ?? coinMeta
            }
            .uniqueBy { $0.uniqueId }
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

    /// Provider tokens not already represented by a local token (by `uniqueId`)
    /// and not user-hidden. Preserves input order — used to fold the dynamic
    /// breadth in *after* the curated/local tokens without duplicating or
    /// re-surfacing a token the user removed.
    func providerTokens(_ tokens: [CoinMeta], excludingLocal localIds: Set<String>, hiddenTokens: [HiddenToken]) -> [CoinMeta] {
        tokens.filter { token in
            !localIds.contains(token.uniqueId) &&
            !hiddenTokens.contains { $0.matches(token) }
        }
    }

    func filteredTokens(chainCoins: [Coin], searchText: String, tokens: [CoinMeta]) -> [CoinMeta] {
        guard !searchText.isEmpty else {
            return []
        }

        // Exclude only the EXACT held tokens (by uniqueId), never every token
        // sharing a held ticker: a ticker exclusion would suppress the badged
        // unverified lookalikes (fake USDC on another contract) that search is
        // meant to reveal — and any legit different-contract same-ticker token.
        let heldIds = Set(
            chainCoins
                .filter { !$0.isNativeToken }
                .map { $0.toCoinMeta().uniqueId }
        )

        let filtered = tokens
            .filter {
                $0.ticker.lowercased().contains(searchText.lowercased()) && !heldIds.contains($0.uniqueId) }
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

    /// Local-first dedup merge: earlier lists win a `uniqueId` collision (so the
    /// curated/local meta is kept), novel tokens are appended in order. Pure +
    /// `static` so the pool ordering/dedup is unit-tested directly.
    static func mergeLocalFirst(_ lists: [[CoinMeta]]) -> [CoinMeta] {
        var seen = Set<String>()
        var result: [CoinMeta] = []
        for list in lists {
            for token in list where seen.insert(token.uniqueId).inserted {
                result.append(token)
            }
        }
        return result
    }
}
