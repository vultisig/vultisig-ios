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
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let result = try await logic.fetchCoins(chain: chain)
            await MainActor.run {
                self.tokens = result.tokens
                self.filteredTokens = result.tokens
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                isLoading = false
            }
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
    private let swapKitTokens: SwapKitTokensCache

    init(
        vault: Vault,
        selectedCoin: Coin,
        isDestination: Bool,
        service: TokenSearchService = .shared,
        swapKitTokens: SwapKitTokensCache = .shared
    ) {
        self.vault = vault
        self.selectedCoin = selectedCoin
        self.isDestination = isDestination
        self.service = service
        self.swapKitTokens = swapKitTokens
    }

    func fetchCoins(chain: Chain) async throws -> SwapCoinSelectionResult {
        let nativeToken = TokensStore.TokenSelectionAssets.first { $0.chain == chain && $0.isNativeToken }

        // Propagate errors instead of swallowing with try?
        let externalTokens = try await service.loadTokens(for: chain)
        let baseTokens = ([nativeToken] + externalTokens).compactMap { $0 }
        let baseUnique = baseTokens.uniqueBy { $0.ticker.lowercased() }

        // SwapKit destinations only — source-side picker stays Phase-1
        // identical. `SwapKitTokensCache.tokens(for:)` already short-circuits
        // when the feature flag is off, but the `isDestination` gate avoids
        // spinning up the fetch task at all on the source side.
        let swapKitBucket: SwapKitTokensBucket
        if isDestination {
            swapKitBucket = await swapKitTokens.tokens(for: chain)
        } else {
            swapKitBucket = SwapKitTokensBucket(chain: chain, byIdentifier: [:], uniqueIds: [])
        }

        // Existing 1inch / Jupiter / preset entries win on overlap — their
        // CoinFactory + price-provider plumbing is already in place. SwapKit
        // contributes any residual tokens (those NOT in the base union).
        let merged = Self.mergeWithSwapKit(
            base: baseUnique,
            swapKit: swapKitBucket
        )
        let sorted = sort(tokens: merged)

        return SwapCoinSelectionResult(tokens: sorted)
    }

    /// Pure-function merge — exposed for tests. Base list keeps its order;
    /// SwapKit-only tokens append after, deduped by `CoinMeta.uniqueId`
    /// (chain + lowercased ticker + lowercased contract).
    static func mergeWithSwapKit(
        base: [CoinMeta],
        swapKit: SwapKitTokensBucket
    ) -> [CoinMeta] {
        let baseIds = Set(base.map { $0.uniqueId })
        let novel = swapKit.tokens.filter { !baseIds.contains($0.uniqueId) }
        return base + novel
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
