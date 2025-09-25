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
    
    @Published var groupedAssets: [Chain: [CoinMeta]] = [:]
    @Published var searchText: String = .empty
    @Published var selection = Set<CoinMeta>()

    var chains: [Chain] {
        groupedAssets
            .map { $0.key }
            .sorted(by: { $0.name < $1.name })
    }
    
    var filteredChains: [Chain] {
        if searchText.isEmpty {
            return groupedAssets.keys.sorted(by: { $0.name < $1.name })
        } else {
            let assets = groupedAssets
                .filter { (chain, tokens) in
                    chain.name.lowercased().contains(searchText.lowercased()) ||
                    tokens.contains { $0.ticker.lowercased().contains(searchText.lowercased()) }
                }
                .map { $0.key }
                .sorted(by: { $0.name < $1.name })
            
            return assets
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
        guard let coins = groupedAssets[chain] else { return false }
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
        })) { $0.chain }
        
        let enableETHSepolia = UserDefaults.standard.bool(forKey: "sepolia")
        if enableETHSepolia {
            groupedAssets[TokensStore.Token.ethSepolia.chain] = [TokensStore.Token.ethSepolia]
        }
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
    
    func filterChains(type: ChainFilterType, vault: Vault) -> [Chain] {
        switch type {
        case .swap:
            return filteredChains
                .filter(\.isSwapAvailable)
        case .send:
            return filteredChains
                .filter { vault.chains.contains($0) }
        }
    }
}
