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

    private let logic: SwapCoinSelectionLogic
    private var cancellable: AnyCancellable?

    init(vault: Vault, selectedCoin: Coin) {
        self.vault = vault
        self.selectedCoin = selectedCoin
        self.logic = SwapCoinSelectionLogic(vault: vault, selectedCoin: selectedCoin)
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
                self.tokens = result
                self.filteredTokens = result
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
            return try? CoinService.shared.addToChain(asset: coin, to: vault, priceProviderId: coin.priceProviderId)
        }
    }
}

// MARK: - SwapCoinSelectionLogic

struct SwapCoinSelectionLogic {
    private let vault: Vault
    private let selectedCoin: Coin
    private let service = TokenSearchService.shared

    init(vault: Vault, selectedCoin: Coin) {
        self.vault = vault
        self.selectedCoin = selectedCoin
    }

    func fetchCoins(chain: Chain) async throws -> [CoinMeta] {
        let nativeToken = TokensStore.TokenSelectionAssets.first { $0.chain == chain && $0.isNativeToken }

        // Propagate errors instead of swallowing with try?
        let externalTokens = try await service.loadTokens(for: chain)
        let tokens = ([nativeToken] + externalTokens).compactMap { $0 }
        let uniqueTokens = tokens.uniqueBy { $0.ticker.lowercased() }
        return sort(tokens: uniqueTokens)
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
