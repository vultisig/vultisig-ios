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
    
    var body: some View {
        AssetSelectionContainerScreen(
            title: "selectChains".localized,
            isPresented: $isPresented,
            searchText: $viewModel.searchText,
            elements: viewModel.filteredChains,
            onSave: onSaveInternal
        ) { asset in
            DefiChainSelectionGridCell(
                chain: asset,
                viewModel: viewModel,
                onSelection: onSelection
            )
        } emptyStateBuilder: {
            emptyStateView
        }
        .withLoading(text: "pleaseWait".localized, isLoading: $isLoading)
        .applySheetSize()
        .onAppear {
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


