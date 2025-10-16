//
//  DefiChainListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct DefiChainListView: View {
    @ObservedObject var vault: Vault
    @ObservedObject var viewModel: DefiMainViewModel
    
    var onCustomizeChains: () -> Void
    
    var body: some View {
        Group {
            if !viewModel.filteredGroups.isEmpty {
                chainList
            } else {
                CustomizeChainsActionBanner(onCustomizeChains: onCustomizeChains)
            }
        }
    }
    
    var chainList: some View {
        ForEach(Array(viewModel.filteredGroups.enumerated()), id: \.element.id) { index, group in
            DefiChainCellView(group: group, vault: vault)
                .commonListItemContainer(
                    index: index,
                    itemsCount: viewModel.filteredGroups.count
                )
        }
    }
}

#Preview {
    DefiChainListView(vault: .example, viewModel: DefiMainViewModel()) {
    }.environmentObject(VaultDetailViewModel())
}
