//
//  VaultMainChainListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VaultMainChainListView: View {
    @ObservedObject var vault: Vault
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var onCopy: (GroupedChain) -> Void
    var onAction: (GroupedChain) -> Void
    var onCustomizeChains: () -> Void
    
    var body: some View {
        Group {
            if !viewModel.filteredGroups.isEmpty {
                chainList
            } else {
                customizeChainsView
            }
        }
    }
    
    var chainList: some View {
        ForEach(Array(viewModel.filteredGroups.enumerated()), id: \.element.id) { index, group in
            VaultChainCellView(group: group, vault: vault) {
                onCopy(group)
            } onAction: {
                onAction(group)
            }
            .commonListItemContainer(
                index: index,
                itemsCount: viewModel.filteredGroups.count
            )
        }
    }
    
    var customizeChainsView: some View {
        ActionBannerView(
            title: "noChainsFound".localized,
            subtitle: "noChainsFoundSubtitle".localized,
            buttonTitle: "customizeChains".localized,
            buttonIcon: "write".localized,
            action: onCustomizeChains
        )
    }
}

#Preview {
    VaultMainChainListView(vault: .example) { _ in
    } onAction: { _ in
        
    } onCustomizeChains: {
        
    }.environmentObject(VaultDetailViewModel())
}
