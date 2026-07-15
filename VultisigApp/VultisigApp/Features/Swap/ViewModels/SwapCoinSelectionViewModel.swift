//
//  SwapCoinSelectionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/08/2025.
//

import Foundation
import Combine

class SwapCoinSelectionViewModel: ObservableObject {
    /// Starts `true` so the picker's first frame renders the loader: the view
    /// falls back to "No result found." whenever `isLoading` is false and
    /// `filteredTokens` is empty, and before the first publish that state
    /// would flash even though nothing has been looked up yet. Cleared by the
    /// first publish (or a failed cold load), after which an empty list is a
    /// genuine no-results state.
    @Published var isLoading: Bool = true
    @Published var tokens: [CoinMeta] = []
    @Published var filteredTokens: [CoinMeta] = []
    @Published var searchText: String = ""
    @Published var error: Error?

    let vault: Vault
    let selectedCoin: Coin
    let isDestination: Bool

    private let logic: SwapCoinSelectionLogic
    private var cancellable: AnyCancellable?

    /// Per-chain cache of the fully-assembled + sorted picker list for the
    /// current picker session. Re-selecting a chain already assembled this
    /// session republishes the cached result in one publish and skips the
    /// whole merge+sort — the dominant cost on rapid back-and-forth switching.
    /// Cleared on `forceRefresh` (first open per presentation), so live balance
    /// changes are picked up on the next forced load. MainActor-isolated: only
    /// touched from `MainActor.run` bodies.
    @MainActor private var memo: [Chain: SwapCoinSelectionResult] = [:]

    @MainActor
    init(
        vault: Vault,
        selectedCoin: Coin,
        isDestination: Bool,
        registry: DestinationTokenRegistry? = nil
    ) {
        self.vault = vault
        self.selectedCoin = selectedCoin
        self.isDestination = isDestination
        self.logic = SwapCoinSelectionLogic(
            vault: vault,
            selectedCoin: selectedCoin,
            isDestination: isDestination,
            registry: registry
        )
    }

    func setup() {
        cancellable = $searchText
            .debounce(for: 0.3, scheduler: DispatchQueue.main)
            .sink { [weak self] searchText in
                guard let self else { return }
                self.filteredTokens = self.logic.filterTokens(searchText: searchText, tokens: self.tokens)
            }
    }

    /// `forceRefresh` is passed to the destination-token registry so the
    /// SwapKit token catalog is re-fetched on the picker's first open per
    /// presentation. The external (curated/1inch/Jupiter) list keeps its own
    /// `SwapTokenListCache` freshness logic — only the destination-registry
    /// catalog is forced.
    func fetchCoins(chain: Chain, forceRefresh: Bool = false) async {
        if forceRefresh {
            // First open per presentation: drop any memoized results so a stale
            // assembled list can't shadow the forced re-fetch.
            await MainActor.run { memo.removeAll() }
        } else if let memoized = await MainActor.run(body: { memo[chain] }) {
            // Re-selecting a chain already assembled this session: republish the
            // cached result in a single publish and skip the whole merge+sort.
            // `filteredTokens` is recomputed from the cached list against the
            // current search text inside `publish`.
            // Bail if a newer chain switch superseded this task — the memoized
            // fast-path skips the cold path's checkCancellation, so without this
            // it could publish the previous chain's list mid-burst.
            guard !Task.isCancelled else { return }
            await MainActor.run { error = nil }
            await publish(memoized)
            return
        }

        // Sync peek on the MainActor: when the chain's vault-independent token
        // list is already cached, do the cheap local merge and publish — the
        // first publish clears `isLoading`, so any spinner (initial state, or
        // a prior chain's cancelled cold load) drops the moment real data
        // lands rather than being cleared up front with nothing to show. A
        // cold load (no cached entry) spins only until its first publish:
        // destination side paints the curated-native + vault-coin list right
        // away, source side when the external list lands.
        let cached = await MainActor.run { SwapTokenListCache.shared.cached(for: chain) }

        if let cached {
            await MainActor.run { error = nil }
            await publishMerge(externalTokens: cached, chain: chain, forceRefresh: forceRefresh)

            // Refresh a stale entry silently in the background — still no
            // spinner. The cache coalesces + fail-opens, so this is cheap.
            let stale = await MainActor.run { SwapTokenListCache.shared.isStale(chain) }
            if stale {
                await refresh(chain: chain)
            }
            return
        }

        // Cold load: no cached list for this chain.
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            // Destination side: even with no external list yet, the curated
            // native + the vault's held coins are already local — paint them
            // immediately (the first publish drops the spinner) instead of
            // blocking the whole picker on the external-catalog fetch plus the
            // registry hop buried in the full merge. The enriched publish
            // below swaps in the complete list. Source side keeps the plain
            // spinner cycle: its list is vault-bounded and arrives in one
            // publish as soon as the external list lands.
            if isDestination {
                let local = await logic.localMerge(externalTokens: [], chain: chain)
                try Task.checkCancellation()
                await publish(local)
            }
            let result = try await logic.fetchCoins(chain: chain, forceRefresh: forceRefresh)
            try Task.checkCancellation()
            await publish(result, memoizeFor: chain)
        } catch is CancellationError {
            // Superseded by a faster chain-switch — leave state for the winner.
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.error = error
                isLoading = false
            }
        }
    }

    /// Background re-fetch of a stale list (via the cache) that republishes the
    /// merge without touching `isLoading`.
    private func refresh(chain: Chain) async {
        do {
            let result = try await logic.fetchCoins(chain: chain)
            try Task.checkCancellation()
            await MainActor.run {
                self.memo[chain] = result
                self.tokens = result.tokens
                self.filteredTokens = self.logic.filterTokens(searchText: self.searchText, tokens: result.tokens)
            }
        } catch {
            // Stale-but-present list is already on screen; swallow refresh
            // failures (the cache fail-opens to last-good anyway).
        }
    }

    private func publishMerge(externalTokens: [CoinMeta], chain: Chain, forceRefresh: Bool = false) async {
        do {
            // Destination side: publish the network-free merge (curated native +
            // cached external list + vault coins) before awaiting the remote
            // destination providers. The registry hop below can take seconds on
            // first open (forced SwapKit catalog + THORChain/Maya pool fetches,
            // awaited sequentially) and the sheet has no "loading more" state —
            // with nothing published it renders "No result found." even though
            // the query is empty. Serving the local list first keeps the picker
            // browsable instantly; provider tokens append on the second publish.
            if isDestination {
                let local = await logic.localMerge(externalTokens: externalTokens, chain: chain)
                try Task.checkCancellation()
                await publish(local)
            }
            let result = try await logic.merge(externalTokens: externalTokens, chain: chain, forceRefresh: forceRefresh)
            try Task.checkCancellation()
            await publish(result, memoizeFor: chain)
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.error = error
                // Terminal state: without a publish the spinner would stay up
                // forever; dropping it lets the view fall back to its empty
                // message.
                self.isLoading = false
            }
        }
    }

    /// Publishes a result to the view. Pass `memoizeFor:` with the chain when
    /// the result is the fully-assembled final list so a later re-select can be
    /// served from the memo — the partial `local` first-paint publishes omit it
    /// (they're intentionally incomplete and must not be cached). `nil` chain
    /// means "publish but don't memoize" (used for the memo-hit republish and
    /// the destination first-paint).
    private func publish(_ result: SwapCoinSelectionResult, memoizeFor chain: Chain? = nil) async {
        await MainActor.run {
            if let chain {
                self.memo[chain] = result
            }
            self.tokens = result.tokens
            self.filteredTokens = self.logic.filterTokens(searchText: self.searchText, tokens: result.tokens)
            self.isLoading = false
        }
    }

    @MainActor func onSelect(coin: CoinMeta) -> Coin? {
        if let vaultCoin = vault.coin(for: coin) {
            return vaultCoin
        } else {
            return try? CoinService.addToChain(asset: coin, to: vault, priceProviderId: coin.priceProviderId)
        }
    }
}

// MARK: - SwapCoinSelectionLogic

/// Result of a single `fetchCoins` call. `tokens` is the picker-ready list
/// (preset + external + SwapKit, deduped, sorted).
struct SwapCoinSelectionResult {
    let tokens: [CoinMeta]
}

struct SwapCoinSelectionLogic {
    private let vault: Vault
    private let selectedCoin: Coin
    private let isDestination: Bool
    private let service: TokenSearchService
    private let registry: DestinationTokenRegistry

    @MainActor
    init(
        vault: Vault,
        selectedCoin: Coin,
        isDestination: Bool,
        service: TokenSearchService = .shared,
        registry: DestinationTokenRegistry? = nil
    ) {
        self.vault = vault
        self.selectedCoin = selectedCoin
        self.isDestination = isDestination
        self.service = service
        // Defaults are resolved inside the body so the MainActor-isolated
        // `.shared` singleton isn't referenced from a default-argument
        // expression (which runs in the caller's context and would warn
        // under Swift 6 strict concurrency). Same pattern as
        // `TransactionHistoryViewModel.init` → `SwapTrackingRegistry.shared`.
        self.registry = registry ?? DestinationTokenRegistry.shared
    }

    func fetchCoins(chain: Chain, forceRefresh: Bool = false) async throws -> SwapCoinSelectionResult {
        // Propagate errors instead of swallowing with try?
        let externalTokens = try await service.loadTokens(for: chain)
        return try await merge(externalTokens: externalTokens, chain: chain, forceRefresh: forceRefresh)
    }

    /// Builds the picker-ready list from an already-fetched external token list
    /// (native + external/preset + destination registry + the vault's held
    /// coins, deduped + sorted). Separated from the network fetch so the view
    /// model can serve a cached external list without a spinner. The vault read
    /// and `sort` (live balance reads) stay on the MainActor.
    func merge(externalTokens: [CoinMeta], chain: Chain, forceRefresh: Bool = false) async throws -> SwapCoinSelectionResult {
        // Destination-side picker pulls in tokens from every registered
        // DestinationTokenProvider; source-side stays vault-bounded since
        // SwapKit + sibling providers add no signal for tokens the user
        // doesn't actually hold.
        let externalBuckets: [DestinationTokenBucket]
        if isDestination {
            externalBuckets = await registry.tokens(for: chain, forceRefresh: forceRefresh)
        } else {
            externalBuckets = []
        }
        return await assemble(externalTokens: externalTokens, chain: chain, externalBuckets: externalBuckets)
    }

    /// Network-free variant of `merge` — assembles the list from what is
    /// already local (curated native + external/preset list + vault coins),
    /// skipping the destination-registry hop. The view model publishes this
    /// first so the destination picker is browsable immediately while the
    /// remote providers (SwapKit catalog, THORChain/Maya pools) are awaited.
    func localMerge(externalTokens: [CoinMeta], chain: Chain) async -> SwapCoinSelectionResult {
        await assemble(externalTokens: externalTokens, chain: chain, externalBuckets: [])
    }

    private func assemble(
        externalTokens: [CoinMeta],
        chain: Chain,
        externalBuckets: [DestinationTokenBucket]
    ) async -> SwapCoinSelectionResult {
        let nativeToken = TokensStore.TokenSelectionAssets.first { $0.chain == chain && $0.isNativeToken }

        let baseTokens = ([nativeToken] + externalTokens).compactMap { $0 }
        let baseUnique = baseTokens.uniqueBy { $0.ticker.lowercased() }

        // Coins the vault actually holds for this chain — including user-added
        // custom tokens that aren't in the curated TokensStore / search list.
        // DeFi-only positions (e.g. staking) aren't swappable, so drop them.
        // `vault`/`selectedCoin` are SwiftData @Model objects, so the reads
        // (`vault.coins(for:)` and `sort`'s `vault.coin(for:)`) must run on the
        // MainActor.
        let vaultTokens = await MainActor.run {
            vault.coins(for: chain).filter { !$0.isDefiOnly }.map { $0.toCoinMeta() }
        }

        let merged = Self.mergeExternal(base: baseUnique, externals: externalBuckets)
        let withVault = Self.merge(base: merged, extra: vaultTokens)
        let deduped = Self.collapseToSingleNative(withVault)

        // Precompute the vault balances on the MainActor (the only place the
        // @Model reads are legal), then run the comparison off the MainActor
        // against the value snapshot. The sort itself no longer calls the O(m)
        // `vault.coin(for:)` linear scan twice per comparison on the main
        // thread — the dominant per-switch cost.
        let snapshot = await makeSortSnapshot(tokens: deduped)
        let sorted = Self.sort(tokens: deduped, snapshot: snapshot)

        return SwapCoinSelectionResult(tokens: sorted)
    }

    /// Pure-function merge — exposed for tests. Base list keeps its order;
    /// novel tokens from each external bucket append after, deduped by
    /// `CoinMeta.uniqueId` (chain + lowercased ticker + lowercased
    /// contract). Same contract as the previous `mergeWithSwapKit`,
    /// generalised over an arbitrary list of provider buckets.
    static func mergeExternal(
        base: [CoinMeta],
        externals: [DestinationTokenBucket]
    ) -> [CoinMeta] {
        merge(base: base, extra: externals.flatMap { $0.tokens })
    }

    /// A chain has exactly one native asset, so the picker must show it once.
    /// External providers (e.g. SwapKit's token list) and legacy persisted
    /// coins can surface that native under a stale ticker — after the Toncoin
    /// rebrand the curated native is `GRAM` while SwapKit still lists `TON`,
    /// which the `uniqueId` dedup treats as distinct and would show as a second
    /// native row (and let it be re-added as a duplicate coin). Keep the first
    /// native — the curated `TokensStore` entry, prepended in `fetchCoins` — and
    /// drop any later native. Non-native tokens are untouched.
    static func collapseToSingleNative(_ tokens: [CoinMeta]) -> [CoinMeta] {
        var keptNative = false
        return tokens.filter { token in
            guard token.isNativeToken else { return true }
            if keptNative { return false }
            keptNative = true
            return true
        }
    }

    /// Appends `extra` tokens not already present in `base`, deduped by
    /// `CoinMeta.uniqueId`. Base order is kept; novel tokens append in
    /// `extra` order.
    static func merge(base: [CoinMeta], extra: [CoinMeta]) -> [CoinMeta] {
        var seen = Set(base.map { $0.uniqueId })
        var result = base
        for token in extra where !seen.contains(token.uniqueId) {
            result.append(token)
            seen.insert(token.uniqueId)
        }
        return result
    }

    /// Value snapshot of the MainActor-only inputs `sort` needs, so the
    /// comparison can run off the MainActor without touching any SwiftData
    /// `@Model`. `balancesByUniqueId` maps each token's `uniqueId` to its vault
    /// fiat balance (resolved once per token via `Vault.coin(for:)` on the
    /// MainActor); `selectedCoinMeta` mirrors the `selectedCoin` read the
    /// selected-first reordering used to make inline.
    struct SortSnapshot: Sendable {
        let balancesByUniqueId: [String: Decimal]
        let selectedCoinMeta: CoinMeta
    }

    /// Builds a `SortSnapshot` on the MainActor. `Vault.coin(for:)` is an O(m)
    /// linear scan; the previous sort called it twice per comparison
    /// (O(n·log n·m)). Here it runs exactly once per token (O(n·m)) and the
    /// off-actor sort does O(1) dictionary lookups against the result. The
    /// mapping mirrors `coin(for:)`'s own prefer-contract-else-ticker rule
    /// because the key is the token's `uniqueId`, resolved by that same method.
    @MainActor
    func makeSortSnapshot(tokens: [CoinMeta]) -> SortSnapshot {
        var balances = [String: Decimal](minimumCapacity: tokens.count)
        for token in tokens {
            balances[token.uniqueId] = vault.coin(for: token)?.balanceInFiatDecimal ?? 0
        }
        return SortSnapshot(
            balancesByUniqueId: balances,
            selectedCoinMeta: selectedCoin.toCoinMeta()
        )
    }

    /// Sorts the picker list off the MainActor using only the value snapshot:
    /// native token first, then descending vault fiat balance, then the
    /// selected coin pinned first. Semantics are identical to the previous
    /// MainActor sort — only the balance reads are pre-resolved into `snapshot`.
    static func sort(tokens: [CoinMeta], snapshot: SortSnapshot) -> [CoinMeta] {
        // Sort coins: native token first, then by USD balance in descending order
        var sortedCoins = tokens.sorted { first, second in
            if first.isNativeToken && !second.isNativeToken {
                return true
            }

            if !first.isNativeToken && second.isNativeToken {
                return false
            }

            // If both are native or both are not native, sort by USD balance
            let firstBalance = snapshot.balancesByUniqueId[first.uniqueId] ?? 0
            let secondBalance = snapshot.balancesByUniqueId[second.uniqueId] ?? 0
            return firstBalance > secondBalance
        }

        // Show the selected coin first. Match on `uniqueId`, not a ticker
        // substring: same-ticker THORChain secured variants (ETH-USDC, BASE-USDC,
        // AVAX-USDC all ticker "USDC") would otherwise promote/duplicate the wrong
        // row and hide a valid one.
        let selectedMeta = snapshot.selectedCoinMeta
        if let index = sortedCoins.firstIndex(where: { $0.uniqueId == selectedMeta.uniqueId }) {
            sortedCoins.remove(at: index)
            sortedCoins = [selectedMeta] + sortedCoins
        }

        return sortedCoins
    }

    func filterTokens(searchText: String, tokens: [CoinMeta]) -> [CoinMeta] {
        guard searchText.isNotEmpty else {
            return tokens
        }

        let filtered = tokens
            .filter { $0.ticker.lowercased().contains(searchText.lowercased()) }
            .prefix(20)
        return Array(filtered)
    }
}
