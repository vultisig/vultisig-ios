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
    @Published var searchText: String = ""
    
    var filteredGroups: [GroupedChain] {
        guard !searchText.isEmpty else {
            return groups
        }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let balanceService = BalanceService.shared
    private var updateBalanceTask: Task<Void, Never>?
    
    var availableActions: [CoinAction] {
        [.swap, .buy, .send, .receive]
    }
    
    @Published var selectedTab: VaultTab = .portfolio
    
    var tabs: [SegmentedControlItem<VaultTab>] = [
        SegmentedControlItem(value: .portfolio, title: "portfolio".localized),
        SegmentedControlItem(value: .nfts, title: "nfts".localized, tag: "soon".localized, isEnabled: false)
    ]
    
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
    
    func categorizeCoins(vault: Vault) {
        var groups = [GroupedChain]()

        for coin in vault.coins {
            addCoin(coin, groups: &groups)
        }

        groups.sort {
            if $0.totalBalanceInFiatDecimal == $1.totalBalanceInFiatDecimal {
                return $0.chain.index < $1.chain.index
            }
            return $0.totalBalanceInFiatDecimal > $1.totalBalanceInFiatDecimal
        }
        self.groups = groups
    }
}

private extension VaultDetailViewModel {
    func getGroup(_ viewModel: CoinSelectionViewModel) async -> GroupedChain? {
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
    
    func addCoin(_ coin: Coin, groups: inout [GroupedChain]) {
        let group = groups.first {
            group in group.address == coin.address && group.chain == coin.chain
        }
        
        guard let group else {
            let chain = GroupedChain(
                chain: coin.chain,
                address: coin.address,
                logo: coin.logo,
                count: 1,
                coins: [coin]
            )
            
            groups.append(chain)
            return
        }
        
        group.coins.append(coin)
        group.count += 1
        if coin.isNativeToken {
            group.logo = coin.logo
        }
        return
    }
}
