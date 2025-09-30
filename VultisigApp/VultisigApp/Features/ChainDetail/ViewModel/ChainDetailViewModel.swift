//
//  ChainDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import Foundation

final class ChainDetailViewModel: ObservableObject {
    private let group: GroupedChain
    private let vault: Vault
    
    @Published var searchText: String = ""
    @Published var selectedTab: ChainDetailTab = .tokens
    
    var tabs: [SegmentedControlItem<ChainDetailTab>] = [
        SegmentedControlItem(value: .tokens, title: "tokens".localized)
    ]
    
    let actionResolver = CoinActionResolver()
    
    @Published var availableActions: [CoinAction] = []
    
    init(vault: Vault, group: GroupedChain) {
        self.vault = vault
        self.group = group
    }
    
    func refresh(group: GroupedChain) {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: group.chain).filtered
        }
    }
    
    var tokens: [Coin] {
        return vault.coins
            .filter { $0.chain == group.chain }
            .sorted {
                if $0.isNativeToken != $1.isNativeToken {
                    return $0.isNativeToken
                }
                return $0.balanceDecimal > $1.balanceDecimal
            }
    }
    
    var filteredTokens: [Coin] {
        if searchText.isEmpty {
            return tokens
        } else {
            let assets = tokens.filter {
                $0.ticker.lowercased().contains(searchText.lowercased())
            }
            
            return assets
        }
    }
}
