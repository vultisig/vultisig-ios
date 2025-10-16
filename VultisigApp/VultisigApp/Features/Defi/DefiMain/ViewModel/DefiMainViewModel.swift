//
//  DefiMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import Foundation

final class DefiMainViewModel: ObservableObject {
    @Published private var groups = [GroupedChain]()
    @Published var searchText: String = ""
    
    private let groupedChainListBuilder = GroupedChainListBuilder()
    
    init() {}
    
    var filteredGroups: [GroupedChain] {
        guard !searchText.isEmpty else {
            return groups
        }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.nativeCoin.ticker.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    func groupChains(vault: Vault) {
        let groups = self.groupedChainListBuilder
            .groupChains(
                for: vault,
                sortedBy: \.totalBalanceInFiatDecimal
            ) { vault.defiChains.contains($0.nativeCoin.chain) }
        self.groups = groups
    }
}
