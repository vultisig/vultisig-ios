//
//  TokenSelectionViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import Foundation
import WalletCore

@MainActor
class CoinSelectionViewModel: ObservableObject {
    
    @Published var groupedAssets: [String: [CoinMeta]] = [:]
    @Published var searchText: String = .empty
    @Published var selection = Set<CoinMeta>()

    var filteredChains: [String] {
        if searchText.isEmpty {
            return groupedAssets.keys.sorted()
        } else {
            return groupedAssets
                .filter { (chain, tokens) in
                    chain.lowercased().contains(searchText.lowercased()) ||
                    tokens.contains { $0.ticker.lowercased().contains(searchText.lowercased()) }
                }
                .map { $0.key }
                .sorted()
        }
    }

    let actionResolver = CoinActionResolver()
    let balanceService = BalanceService.shared
    
    func loadData(coin: Coin) async {
        await balanceService.updateBalance(for: coin)
    }
    
    func setData(for vault: Vault) {
        groupAssets()
        checkSelected(for: vault)
    }
    
    func hasTokens(chain: Chain) -> Bool {
        guard let coins = groupedAssets[chain.name] else { return false }
        return coins.count > 1
    }
    
    private func checkSelected(for vault: Vault) {
        selection = Set(vault.coins.map{$0.toCoinMeta()})
    }
    
    private func groupAssets() {
        groupedAssets = [:]
        groupedAssets = Dictionary(grouping: TokensStore.TokenSelectionAssets.sorted(by: { first, second in
            if first.isNativeToken {
                return true
            }
            return false
        })) { $0.chain.name }
    }

    func isSelected(asset: CoinMeta) -> Bool {
        return selection.contains(where: { $0.chain == asset.chain && $0.ticker.lowercased() == asset.ticker.lowercased() })
    }

    func handleSelection(isSelected: Bool, asset: CoinMeta) {
        if isSelected {
            selection.insert(asset)
        } else {
            selection.remove(asset)
        }
    }

    func selectWeweIfNeeded(vault: Vault) {
        guard !selection.contains(TokensStore.Token.baseWewe) else { return }

        Task {
            selection.insert(TokensStore.Token.baseWewe)
            await CoinService.saveAssets(for: vault, selection: selection)
        }
    }
}
