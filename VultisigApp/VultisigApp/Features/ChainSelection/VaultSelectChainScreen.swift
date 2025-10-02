//
//  VaultSelectChainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct VaultSelectChainScreen: View {
    @ObservedObject var vault: Vault
    @Binding var isPresented: Bool
    var onSave: () -> Void
    @State var searchBarFocused: Bool = false
        
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    var body: some View {
        AssetSelectionContainerScreen(
            title: "selectChains".localized,
            isPresented: $isPresented,
            searchText: $viewModel.searchText,
            elements: viewModel.filteredChains,
            onSave: onSaveInternal
        ) { asset in
            ChainSelectionGridCell(
                assets: viewModel.groupedAssets[asset] ?? [],
                onSelection: onSelection
            )
        } emptyStateBuilder: {
            emptyStateView
        }
        .onLoad {
            viewModel.setData(for: vault)
        }
    }
    
    var emptyStateView: some View {
        VStack {
            VStack(spacing: 12) {
                Icon(named: "crypto", color: Theme.colors.primaryAccent4, size: 24)
                Text("noChainsFound")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSecondary))
            Spacer()
        }
    }
}

private extension VaultSelectChainScreen {
    func onSaveInternal() {
        Task {
            await saveAssets()
            onSave()
        }
        isPresented.toggle()
    }
    
    func onSelection(_ chainSelection: ChainSelection) {
        viewModel.handleSelection(isSelected: chainSelection.selected, asset: chainSelection.asset)
    }
    
    func saveAssets() async {
        await CoinService.saveAssets(for: vault, selection: viewModel.selection)
    }
}


#Preview {
    VaultSelectChainScreen(
        vault: .example,
        isPresented: .constant(true),
        onSave: {}
    )
}


