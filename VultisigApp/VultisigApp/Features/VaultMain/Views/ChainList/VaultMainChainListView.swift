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
    var onCustomizeChains: () -> Void
    
    var body: some View {
        Group {
            if !viewModel.filteredGroups.isEmpty {
                chainList
            } else {
                customizeChainsView
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
        ForEach(Array(viewModel.filteredGroups.enumerated()), id: \.element.id) { index, group in
            let isFirst = index == 0
            let isLast = index == viewModel.filteredGroups.count - 1
            
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
    
    var customizeChainsView: some View {
        VStack(spacing: 12) {
            Icon(named: "crypto-outline", color: Theme.colors.primaryAccent4, size: 24)
            VStack(spacing: 8) {
                Text("noChainsFound")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
                Text("noChainsFoundSubtitle")
                    .foregroundStyle(Theme.colors.textExtraLight)
                    .font(Theme.fonts.footnote)
            }
            .frame(maxWidth: 263)
            .multilineTextAlignment(.center)
          
            PrimaryButton(title: "customizeChains", leadingIcon: "write", size: .mini, action: onCustomizeChains)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSecondary))
    }
}

#Preview {
    VaultMainChainListView(vault: .example) { _ in
    } onAction: { _ in
        
    } onCustomizeChains: {
        
    }.environmentObject(VaultDetailViewModel())
}
