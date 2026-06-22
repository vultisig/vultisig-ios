//
//  SwapCoinSelectionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/08/2025.
//

import Foundation
import Combine

class SwapCoinSelectionViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var tokens: [CoinMeta] = []
    @Published var filteredTokens: [CoinMeta] = []
    @Published var searchText: String = ""
    @Published var error: Error?

    let vault: Vault
    let selectedCoin: Coin
    let isDestination: Bool

    private let logic: SwapCoinSelectionLogic
    private var cancellable: AnyCancellable?

    @MainActor
    init(vault: Vault, selectedCoin: Coin, isDestination: Bool) {
        self.vault = vault
        self.selectedCoin = selectedCoin
        self.isDestination = isDestination
        self.logic = SwapCoinSelectionLogic(
            vault: vault,
            selectedCoin: selectedCoin,
            isDestination: isDestination
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

    func fetchCoins(chain: Chain) async {
        // Sync peek on the MainActor: when the chain's vault-independent token
        // list is already cached, do the cheap local merge and publish without
        // ever flipping `isLoading` — instant, no spinner. Only a cold load
        // (no cached entry) shows the loader.
        let cached = await MainActor.run { SwapTokenListCache.shared.cached(for: chain) }

        if let cached {
            await MainActor.run {
                error = nil
                // A prior cold load for another chain may have been cancelled
                // with the spinner still up — clear it so the instant-serve
                // path is truly spinner-free.
                isLoading = false
            }
            await publishMerge(externalTokens: cached, chain: chain)

            // Refresh a stale entry silently in the background — still no
            // spinner. The cache coalesces + fail-opens, so this is cheap.
            let stale = await MainActor.run { SwapTokenListCache.shared.isStale(chain) }
            if stale {
                await refresh(chain: chain)
            }
            return
        }

        // Cold load: no cached list for this chain — show the spinner.
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let result = try await logic.fetchCoins(chain: chain)
            try Task.checkCancellation()
            await MainActor.run {
                self.tokens = result.tokens
                self.filteredTokens = result.tokens
                isLoading = false
            }
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
                self.tokens = result.tokens
                self.filteredTokens = self.logic.filterTokens(searchText: self.searchText, tokens: result.tokens)
            }
        } catch {
            // Stale-but-present list is already on screen; swallow refresh
            // failures (the cache fail-opens to last-good anyway).
        }
    }

    private func publishMerge(externalTokens: [CoinMeta], chain: Chain) async {
        do {
            let result = try await logic.merge(externalTokens: externalTokens, chain: chain)
            try Task.checkCancellation()
            await MainActor.run {
                self.tokens = result.tokens
                self.filteredTokens = self.logic.filterTokens(searchText: self.searchText, tokens: result.tokens)
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run { self.error = error }
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

    func fetchCoins(chain: Chain) async throws -> SwapCoinSelectionResult {
        // Propagate errors instead of swallowing with try?
        let externalTokens = try await service.loadTokens(for: chain)
        return try await merge(externalTokens: externalTokens, chain: chain)
    }

    /// Builds the picker-ready list from an already-fetched external token list
    /// (native + external/preset + destination registry + the vault's held
    /// coins, deduped + sorted). Separated from the network fetch so the view
    /// model can serve a cached external list without a spinner. The vault read
    /// and `sort` (live balance reads) stay on the MainActor.
    func merge(externalTokens: [CoinMeta], chain: Chain) async throws -> SwapCoinSelectionResult {
        let nativeToken = TokensStore.TokenSelectionAssets.first { $0.chain == chain && $0.isNativeToken }

        let baseTokens = ([nativeToken] + externalTokens).compactMap { $0 }
        let baseUnique = baseTokens.uniqueBy { $0.ticker.lowercased() }

        // Destination-side picker pulls in tokens from every registered
        // DestinationTokenProvider; source-side stays vault-bounded since
        // SwapKit + sibling providers add no signal for tokens the user
        // doesn't actually hold.
        let externalBuckets: [DestinationTokenBucket]
        if isDestination {
            externalBuckets = await registry.tokens(for: chain)
        } else {
            externalBuckets = []
        }

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
        let sorted = await MainActor.run { sort(tokens: deduped) }

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

    func sort(tokens: [CoinMeta]) -> [CoinMeta] {
        // Sort coins: native token first, then by USD balance in descending order
        var sortedCoins = tokens.sorted { first, second in
            if first.isNativeToken && !second.isNativeToken {
                return true
            }

            if !first.isNativeToken && second.isNativeToken {
                return false
            }

            let firstCoin = vault.coin(for: first)
            let secondCoin = vault.coin(for: second)

            // If both are native or both are not native, sort by USD balance
            return firstCoin?.balanceInFiatDecimal ?? 0 > secondCoin?.balanceInFiatDecimal ?? 0
        }

        // Show selected first
        if selectedCoin.chain == sortedCoins.first?.chain, let index = sortedCoins.firstIndex(where: { $0.ticker.localizedCaseInsensitiveContains(selectedCoin.ticker)}) {
            sortedCoins.remove(at: index)
            sortedCoins = [selectedCoin.toCoinMeta()] + sortedCoins
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
