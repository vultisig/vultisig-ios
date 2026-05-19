//
//  VaultSelectChainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct VaultSelectChainScreen: View {
    @ObservedObject var vault: Vault
    let preselectChains: Bool
    @Binding var isPresented: Bool
    var onSave: () -> Void
    /// Invoked when the user taps a chain that requires a yet-unprovisioned
    /// MLDSA key (today: QBTC). Caller is expected to dismiss this sheet and
    /// drive the user through `KeygenRoute.quantumSecurityIntro`. When `nil`,
    /// such chains are hidden entirely (legacy behavior used by onboarding).
    var onRequireQuantumKeygen: ((CoinMeta) -> Void)?
    @State var searchBarFocused: Bool = false
    @State var isLoading: Bool = false

    @StateObject var viewModel = CoinSelectionViewModel()

    init(
        vault: Vault,
        preselectChains: Bool = true,
        isPresented: Binding<Bool>,
        onRequireQuantumKeygen: ((CoinMeta) -> Void)? = nil,
        onSave: @escaping () -> Void
    ) {
        self.vault = vault
        self.preselectChains = preselectChains
        self._isPresented = isPresented
        self.onRequireQuantumKeygen = onRequireQuantumKeygen
        self.onSave = onSave
    }

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
            ChainSelectionGridCell(
                assets: viewModel.groupedAssets[asset] ?? [],
                isSelected: isSelected(chain: asset),
                onSelection: onSelection
            )
        } emptyStateBuilder: {
            ChainNotFoundEmptyStateView()
        }
        .withLoading(text: "pleaseWait".localized, isLoading: $isLoading)
        .onLoad {
            viewModel.showMldsaChainsWithoutKey = onRequireQuantumKeygen != nil
            viewModel.setData(for: vault, checkForSelected: preselectChains)
        }
    }

    func isSelected(chain: Chain) -> Bool {
        return viewModel.selection.contains { $0.chain == chain }
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
        if chainSelection.selected,
           let onRequireQuantumKeygen,
           viewModel.requiresQuantumKeygen(for: chainSelection.asset, vault: vault) {
            onRequireQuantumKeygen(chainSelection.asset)
            return
        }
        viewModel.handleSelection(isSelected: chainSelection.selected, asset: chainSelection.asset)
    }

    func saveAssets() async {
        /// When it comes from onboarding, if the selection is empty we keep default chains
        if !preselectChains, viewModel.selection.isEmpty {
            return
        }

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
