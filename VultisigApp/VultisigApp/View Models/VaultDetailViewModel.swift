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
    @Published var selectedGroup: GroupedChain? = nil
    @Published var groups = [GroupedChain]()

    private let balanceService = BalanceService.shared
    private var updateBalanceTask: Task<Void, Never>?

    func migrate(vault: Vault) {
        // MATIC to POL migration
        for coin in vault.coins where coin.ticker == "MATIC" {
            coin.ticker = "POL"
            coin.logo = "pol"
        }
    }

    func updateBalance(vault: Vault) {
        updateBalanceTask?.cancel()
        updateBalanceTask = Task {
            await balanceService.updateBalances(vault: vault)
            if !Task.isCancelled {
                categorizeCoins(vault: vault)
            }
        }
    }
    
    func getGroupAsync(_ viewModel: CoinSelectionViewModel) {
        Task {
            selectedGroup = await getGroup(viewModel)
        }
    }
    
    private func getGroup(_ viewModel: CoinSelectionViewModel) async -> GroupedChain? {
        for group in groups {
            let actions = await viewModel.actionResolver.resolveActions(for: group.chain)
            
            for action in actions {
                if action == .swap {
                    return group
                }
            }
        }
        return groups.first
    }
    
    func categorizeCoins(vault: Vault) {
        groups = [GroupedChain]()

        for coin in vault.coins {
            addCoin(coin)
        }

        groups.sort { $0.chain.index < $1.chain.index    }
        groups.sort { $0.totalBalanceInFiatDecimal > $1.totalBalanceInFiatDecimal }
    }
    
    private func addCoin(_ coin: Coin) {
        for group in groups {
            if group.address == coin.address && group.name == coin.chain.name {
                group.coins.append(coin)
                group.count += 1
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
        
        groups.append(chain)
    }
}
