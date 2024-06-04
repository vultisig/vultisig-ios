//
//  VaultDetailViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation
import SwiftUI

@MainActor
class VaultDetailViewModel: ObservableObject {
    @Published var coinsGroupedByChains = [GroupedChain]()
    @Published var selectedGroup: GroupedChain? = nil
    let balanceService = BalanceService.shared
    private var updateBalanceTask: Task<Void, Never>?
    func updateBalance() {
        updateBalanceTask?.cancel()
        updateBalanceTask = Task {
            let coins = coinsGroupedByChains.reduce([]) { $0 + $1.coins }
            await balanceService.updateBalances(coins: coins)
        }
    }
    
    func setOrder() {
        for index in 0..<coinsGroupedByChains.count {
            coinsGroupedByChains[index].setOrder(index)
        }
    }
    
    
    func fetchCoins(for vault: Vault) {
        categorizeCoins(vault: vault)
    }
    
    func getGroupAsync(_ viewModel: CoinSelectionViewModel) {
        Task {
            selectedGroup = await getGroup(viewModel)
        }
    }
    
    private func getGroup(_ viewModel: CoinSelectionViewModel) async -> GroupedChain? {
        for group in coinsGroupedByChains {
            let actions = await viewModel.actionResolver.resolveActions(for: group.chain)
            
            for action in actions {
                if action == .swap {
                    return group
                }
            }
        }
        return coinsGroupedByChains.first
    }
    
    private func categorizeCoins(vault: Vault) {
        coinsGroupedByChains = [GroupedChain]()
        
        for coin in vault.coins {
            addCoin(coin)
        }
        coinsGroupedByChains.sort { $0.name < $1.name }
    }
    
    private func addCoin(_ coin: Coin) {
        for group in coinsGroupedByChains {
            if group.address == coin.address && group.name == coin.chain.name {
                group.coins.append(coin)
                group.count+=1
                if coin.isNativeToken {
                    group.logo = coin.logo
                }
                return
            }
        }
        
        let chain = GroupedChain(
            chain: coin.chain,
            address: coin.address,
            logo: coin.logo,
            count: 1,
            coins: [coin]
        )
        coinsGroupedByChains.append(chain)
    }
}
