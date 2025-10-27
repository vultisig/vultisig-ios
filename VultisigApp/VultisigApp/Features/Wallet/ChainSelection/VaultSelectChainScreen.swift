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
    @State var isLoading: Bool = false
        
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    var body: some View {
        AssetSelectionContainerScreen(
            title: "selectChains".localized,
            isPresented: $isPresented,
            searchText: $viewModel.searchText,
            elements: [AssetSection(assets: viewModel.filteredChains)],
            onSave: onSaveInternal
        ) { asset, _ in
            ChainSelectionGridCell(
                assets: viewModel.groupedAssets[asset] ?? [],
                onSelection: onSelection
            )
        } emptyStateBuilder: {
            ChainNotFoundEmptyStateView()
        }
        .withLoading(text: "pleaseWait".localized, isLoading: $isLoading)
        .onLoad {
            viewModel.setData(for: vault)
        }
    }
}

private extension VaultSelectChainScreen {
    func onSaveInternal() {
        isLoading = true
        Task {
            await saveAssets()
            await MainActor.run {
                isLoading = false
                onSave()
                isPresented.toggle()
            }
        }
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


