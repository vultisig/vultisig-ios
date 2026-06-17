//
//  DefiSelectChainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

/// Represents a selectable item in the DeFi chain selection screen
enum DefiSelectableItem: Hashable, Identifiable {
    case circle
    case noon
    case chain(Chain)

    var id: String {
        switch self {
        case .circle:
            return "circle"
        case .noon:
            return "noon"
        case .chain(let chain):
            return chain.rawValue
        }
    }
}

struct DefiSelectChainScreen: View {
    @ObservedObject var vault: Vault
    @Binding var isPresented: Bool
    var onSave: () -> Void
    @State var searchBarFocused: Bool = false
    @State var isLoading: Bool = false
    @State private var error: HelperError?

    @StateObject var viewModel = DefiSelectChainViewModel()

    var selectableItems: [DefiSelectableItem] {
        var items: [DefiSelectableItem] = []

        // Add Circle if it matches the search filter
        if viewModel.shouldShowCircle {
            items.append(.circle)
        }

        // Add Noon if it matches the search filter
        if viewModel.shouldShowNoon {
            items.append(.noon)
        }

        // Add filtered chains
        items.append(contentsOf: viewModel.filteredChains.map { .chain($0) })

        return items
    }

    var sections: [AssetSection<Int, DefiSelectableItem>] {
        !selectableItems.isEmpty ? [AssetSection(assets: selectableItems)] : []
    }

    var body: some View {
        AssetSelectionContainerSheet(
            title: "selectChains".localized,
            isPresented: $isPresented,
            searchText: $viewModel.searchText,
            elements: sections,
            onSave: onSaveInternal,
            cellBuilder: cellBuilder,
            emptyStateBuilder: { ChainNotFoundEmptyStateView() }
        )
        .withLoading(text: "pleaseWait".localized, isLoading: $isLoading)
        .applySheetSize()
        .onAppear {
            viewModel.setData(for: vault)
        }
        .alert(item: $error) { error in
            Alert(
                title: Text("error".localized),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("ok".localized))
            )
        }
    }

    @ViewBuilder
    func cellBuilder(item: DefiSelectableItem, sectionType _: Int) -> some View {
        switch item {
        case .circle:
            DefiYieldSelectionGridCell(
                name: "circleTitle".localized,
                logo: "circle-logo",
                isEnabled: viewModel.isCircleEnabled,
                onSelection: onCircleSelection
            )
        case .noon:
            DefiYieldSelectionGridCell(
                name: "noonTitle".localized,
                logo: "noon",
                isEnabled: viewModel.isNoonEnabled,
                onSelection: onNoonSelection
            )
        case .chain(let chain):
            DefiChainSelectionGridCell(
                chain: chain,
                viewModel: viewModel,
                onSelection: onSelection
            )
        }
    }
}

private extension DefiSelectChainScreen {
    func onSaveInternal() {
        isLoading = true
        Task {
            do {
                try await viewModel.save(for: vault)
                await MainActor.run {
                    isLoading = false
                    onSave()
                    isPresented.toggle()
                }
            } catch {
                // Keep the sheet open so the user can retry instead of losing
                // their selection to a silently-dropped save.
                await MainActor.run {
                    isLoading = false
                    self.error = .runtimeError(error.localizedDescription)
                }
            }
        }
    }

    func onSelection(_ chainSelection: DefiChainSelection) {
        viewModel.handleSelection(isSelected: chainSelection.selected, chain: chainSelection.chain)
    }

    func onCircleSelection(_ isSelected: Bool) {
        viewModel.handleCircleSelection(isSelected: isSelected)
    }

    func onNoonSelection(_ isSelected: Bool) {
        viewModel.handleNoonSelection(isSelected: isSelected)
    }
}

#Preview {
    DefiSelectChainScreen(
        vault: .example,
        isPresented: .constant(true),
        onSave: {}
    )
}
