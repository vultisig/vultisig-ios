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
    @EnvironmentObject var tokenSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var onCopy: (GroupedChain) -> Void
    var onAction: (GroupedChain) -> Void
    
    var body: some View {
        Group {
            if viewModel.groups.isEmpty {
                Text("No chains selected. Please add one")
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)
            } else {
                chainList
            }
        }
        .onAppear {
            viewModel.updateBalance(vault: vault)
            viewModel.getGroupAsync(tokenSelectionViewModel)
            
            tokenSelectionViewModel.setData(for: vault)
            settingsDefaultChainViewModel.setData(tokenSelectionViewModel.groupedAssets)
            viewModel.categorizeCoins(vault: vault)
        }
    }
    
    var chainList: some View {
        ForEach(Array(viewModel.groups.enumerated()), id: \.element.id) { index, group in
            let isFirst = index == 0
            let isLast = index == viewModel.groups.count - 1
            
            VStack(spacing: 0) {
                GradientListSeparator()
                    .showIf(isFirst)
                VaultChainCellView(group: group, vault: vault) {
                    onCopy(group)
                } onAction: {
                    onAction(group)
                }
                Separator(color: Theme.colors.borderLight, opacity: 1)
                    .showIf(!isLast)
            }
            .clipShape(
                .rect(
                    topLeadingRadius: isFirst ? 12 : 0,
                    bottomLeadingRadius: isLast ? 12 : 0,
                    bottomTrailingRadius: isLast ? 12 : 0,
                    topTrailingRadius: isFirst ? 12 : 0
                )
            )
        }
    }
}

#Preview {
    VaultMainChainListView(vault: .example) { _ in
    } onAction: { _ in
        
    }.environmentObject(VaultDetailViewModel())
}
