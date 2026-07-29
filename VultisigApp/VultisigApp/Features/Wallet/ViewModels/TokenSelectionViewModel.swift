//
//  TokenSelectionViewModel.swift
//  VultisigApp
//

import SwiftUI

@MainActor
class TokenSelectionViewModel: ObservableObject {

    /// Re-filters on `didSet` — i.e. AFTER the new value is stored. Driving this
    /// from `$searchText` instead is a trap: `@Published` fires its publisher in
    /// `willSet`, so a subscriber that reads `searchText` back (rather than using
    /// the emitted value) filters against the PREVIOUS keystroke — type `USDCC`
    /// and you get the results for `USDC`, delete the `C` and `USDC` disappears.
    @Published var searchText: String = .empty {
        didSet { updateSearchedTokens(query: searchText) }
    }
    /// Held non-native coins for the chain (browse, shown first).
    @Published var selectedTokens: [CoinMeta] = []
    /// Curated `TokensStore` presets not held/hidden (browse, after held). Always
    /// present synchronously — independent of the async provider fetch.
    @Published var preExistTokens: [CoinMeta] = []
    /// Verified provider breadth for browse (1inch / Jupiter), deduped against
    /// the local tokens above and capped to the best
    /// `TokenSelectionLogic.browseTokensPerProvider` of EACH provider. Empty
    /// until the provider fetch lands. Search is not capped this way — it reads
    /// `searchableTokens`, which holds the full breadth.
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
    /// `uniqueId → provider kind`, so browse caps each provider's breadth
    /// separately (a two-provider chain shows two capped groups, not one).
    private var catalogSourceKinds: [String: String] = [:]
    /// The full local-first search pool (curated presets + verified + unverified),
    /// filtered by the query into `searchedTokens`. Always contains the presets
    /// so a curated/local token stays searchable even when the provider fetch
    /// is pending or fails.
    private var searchableTokens: [CoinMeta] = []
    /// The chain the retained catalog above belongs to. A failed fetch keeps the
    /// last-good catalog (better than blanking the list) — but only for the SAME
    /// chain: retaining it across a chain change would browse and search another
    /// chain's tokens.
    private var catalogChain: Chain?

    private var loadingTask: Task<Void, Never>?

    private let logic = TokenSelectionLogic.shared
    private let loadCatalog: (Chain) async throws -> TokenSearchResult

    /// `loadCatalog` is injectable so tests can drive the provider outcome
    /// (including a throw) without the network. Production uses the shared
    /// `TokenSearchService`.
    init(loadCatalog: @escaping (Chain) async throws -> TokenSearchResult = { try await TokenSearchService.shared.loadCatalog(for: $0) }) {
        self.loadCatalog = loadCatalog
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

        if catalogChain != chain {
            discardRetainedCatalog()
        }

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

    /// Re-filters the already-built pool against `query`. Takes the query as a
    /// parameter rather than reading `searchText` so it can never observe a
    /// half-applied edit. No vault read is needed — the pool is derived in
    /// `recompute` and already carries the vault's held tokens.
    func updateSearchedTokens(query: String) {
        searchedTokens = logic.filteredTokens(searchText: query, tokens: searchableTokens)
    }

    /// Drop everything derived from a provider fetch. Called when the screen is
    /// asked for a different chain than the retained catalog belongs to.
    private func discardRetainedCatalog() {
        catalogSurfaceable = []
        catalogUnverified = []
        catalogSourceKinds = [:]
        verificationByUniqueId = [:]
        catalogChain = nil
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
            catalogSourceKinds = result.sourceKindByUniqueId
            verificationByUniqueId = result.verificationByUniqueId
            catalogChain = chain
        } catch {
            // Fail open: keep the local presets/held (already rendered) fully
            // searchable rather than blanking the list, and re-derive from what's
            // local below. The error is recorded (not rendered) — the catalog has
            // no failure the user can act on: providers already fail open to the
            // bundled floor + last-good disk snapshot, so there is nothing to retry.
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
    /// shows curated/local + the best N of each provider's verified breadth;
    /// search spans the FULL breadth and adds the badged unverified long-tail.
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

        // Cap AFTER the local/hidden exclusion, so a curated or user-hidden
        // token can't eat one of a provider's slots and leave browse showing
        // fewer than the cap in genuinely new tokens.
        browseProviderTokens = TokenSelectionLogic.cappedPerProvider(
            verifiedBreadth,
            sourceKindByUniqueId: catalogSourceKinds
        )
        // Held tokens lead the search pool. Excluding them (they're "already
        // added") makes a search for a token the vault holds return NOTHING,
        // which reads as the catalog being broken — search a held VULT on
        // Ethereum and the curated token is simply absent. They render with
        // their selected checkmark, so being held is already visible.
        searchableTokens = TokenSelectionLogic.mergeLocalFirst(
            [selectedTokens, preExistTokens, verifiedBreadth, unverifiedBreadth]
        )
        searchedTokens = logic.filteredTokens(searchText: searchText, tokens: searchableTokens)
    }
}

// MARK: - TokenSelectionLogic

struct TokenSelectionLogic {
    static let shared = TokenSelectionLogic()

    /// How many of each provider's tokens browse shows before the user types.
    /// The providers now return their lists best-first, so this is "the best N
    /// per source", not an arbitrary truncation — 1inch alone offers ~2,200
    /// tokens on Ethereum, which is not a list anyone scans.
    ///
    /// This bounds BROWSE only. `searchableTokens` keeps the full breadth, so
    /// this can never be the reason a token isn't found.
    static let browseTokensPerProvider = 20

    /// How many matches a search renders. Unrelated to `browseTokensPerProvider`
    /// — this one bounds the rendered result of a query, and the query has
    /// already narrowed the pool.
    static let searchResultLimit = 20

    private init() {}

    /// Takes the first `limit` tokens of EACH provider, preserving order.
    ///
    /// Per-provider rather than global: a chain served by two providers shows up
    /// to `2 × limit`, a chain served by one shows `limit`, and a slow or empty
    /// provider can't be crowded out by a fast one. Grouping is by the provider
    /// `kind` that won the token in the catalog merge.
    ///
    /// Tokens with no known source share a single bucket rather than escaping
    /// the cap — an unattributed token should shrink the list, not uncap it.
    static func cappedPerProvider(
        _ tokens: [CoinMeta],
        sourceKindByUniqueId: [String: String],
        limit: Int = browseTokensPerProvider
    ) -> [CoinMeta] {
        var shownPerSource: [String: Int] = [:]
        return tokens.filter { token in
            let source = sourceKindByUniqueId[token.uniqueId] ?? .empty
            let shown = shownPerSource[source, default: 0]
            guard shown < limit else { return false }
            shownPerSource[source] = shown + 1
            return true
        }
    }

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
        // Exclude a curated preset only when the vault holds THAT exact token
        // (by uniqueId), never every preset sharing a held ticker: a ticker match
        // would drop the vetted `USDC` preset from browse whenever the vault
        // holds a lookalike `USDC` on a different contract.
        let heldIds = Set(
            chainCoins
                .filter { !$0.isNativeToken }
                .map { $0.toCoinMeta().uniqueId }
        )

        // The curated per-chain floor is sourced through the catalog's bundled
        // provider (already scoped to `chain`) rather than reading the preset
        // array directly. The dynamic overlay for this screen is unchanged — it
        // still flows through `loadExternalTokens` -> `TokenSearchService`.
        return BundledTokensProvider.curatedTokens(for: chain, defaults: .standard)
            .filter { token in
                !token.isNativeToken &&
                !heldIds.contains(token.uniqueId) &&
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

    /// Ticker matches over the whole local-first pool. Nothing is excluded here:
    /// the pool already holds each token exactly once (deduped by `uniqueId`),
    /// held tokens included, so search finds everything browse can show plus the
    /// badged unverified long-tail. A same-ticker lookalike on a different
    /// contract is a distinct `uniqueId` and is revealed alongside the real one —
    /// that visibility is the point of the badge.
    func filteredTokens(searchText: String, tokens: [CoinMeta]) -> [CoinMeta] {
        guard !searchText.isEmpty else {
            return []
        }

        let filtered = tokens
            .filter { $0.ticker.lowercased().contains(searchText.lowercased()) }
            .prefix(Self.searchResultLimit)

        return Array(filtered)
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
