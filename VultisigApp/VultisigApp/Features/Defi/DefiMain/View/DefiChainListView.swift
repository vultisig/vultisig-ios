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
    
    var onGroup: (GroupedChain) -> Void
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
//            NavigationLink {
//                switch group.chain {
//                case .thorChain, .mayaChain:
//                    DefiChainMainScreen(vault: vault, group: group)
//                default:
//                    EmptyView()
//                }
//            } label: {
            Button {
                onGroup(group)
            } label: {
                DefiChainCellView(group: group, vault: vault)
                    .commonListItemContainer(
                        index: index,
                        itemsCount: viewModel.filteredGroups.count
                    )
            }.buttonStyle(.plain)
  
//            }
        }
    }
}

#Preview {
    DefiChainListView(
        vault: .example,
        viewModel: DefiMainViewModel()
    ) {_ in } onCustomizeChains: {}
        .environmentObject(VaultDetailViewModel())
}
