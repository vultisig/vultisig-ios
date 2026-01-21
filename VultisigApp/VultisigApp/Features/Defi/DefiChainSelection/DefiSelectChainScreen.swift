//
//  DefiSelectChainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct DefiSelectChainScreen: View {
    @ObservedObject var vault: Vault
    @Binding var isPresented: Bool
    var onSave: () -> Void
    @State var searchBarFocused: Bool = false
    @State var isLoading: Bool = false
        
    @StateObject var viewModel = DefiSelectChainViewModel()
    
    var sections: [AssetSection<Int, Chain>] {
        !viewModel.filteredChains.isEmpty ? [AssetSection(assets: viewModel.filteredChains)] : []
    }
    
    var body: some View {
        AssetSelectionContainerSheet(
            title: "selectChains".localized,
            isPresented: $isPresented,
            searchText: $viewModel.searchText,
            elements: sections,
            onSave: onSaveInternal
        ) { asset, _ in
            DefiChainSelectionGridCell(
                chain: asset,
                viewModel: viewModel,
                onSelection: onSelection
            )
        } emptyStateBuilder: {
            ChainNotFoundEmptyStateView()
        }
        .withLoading(text: "pleaseWait".localized, isLoading: $isLoading)
        .applySheetSize()
        .onAppear {
            viewModel.setData(for: vault)
        }
    }
}

private extension DefiSelectChainScreen {
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
    
    func onSelection(_ chainSelection: DefiChainSelection) {
        viewModel.handleSelection(isSelected: chainSelection.selected, chain: chainSelection.chain)
    }
    
    func saveAssets() async {
        await viewModel.save(for: vault)
    }
}

#Preview {
    DefiSelectChainScreen(
        vault: .example,
        isPresented: .constant(true),
        onSave: {}
    )
}
