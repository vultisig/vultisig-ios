//
//  KeyImportCustomizeChainsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import SwiftUI

struct KeyImportCustomizeChainsView: View {
    @ObservedObject var viewModel: KeyImportChainsSetupViewModel
    let onImport: () -> Void

    @State var searchText: String = ""
    @State var items: [Chain] = []
    @State private var showDerivationSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AssetSelectionContainerView(
                searchText: $searchText,
                elements: [AssetSection(type: 0, assets: items)],
                cellBuilder: { chain, _ in cell(for: chain) },
                emptyStateBuilder: { EmptyView() }
            )

            PrimaryButton(
                title: "continue".localized,
                action: onImport
            )
            .disabled(viewModel.buttonDisabled)
        }
        .onLoad { items = Chain.keyImportEnabledChains }
        .onChange(of: searchText) { _, newValue in
            items = newValue.isEmpty ? Chain.keyImportEnabledChains : Chain.keyImportEnabledChains.filter {
                $0.name.localizedCaseInsensitiveContains(newValue) || $0.ticker.localizedCaseInsensitiveContains(newValue)
            }
        }
        .crossPlatformSheet(isPresented: $showDerivationSheet) {
            DerivationPathSelectionSheet(
                chain: .solana,
                selectedPath: $viewModel.selectedDerivationPath,
                isPresented: $showDerivationSheet,
                onSelect: { path in
                    viewModel.selectDerivationPath(path, for: .solana)
                    onImport()
                }
            )
        }
    }

    func cell(for chain: Chain) -> some View {
        AssetSelectionGridCell(
            name: chain.name,
            ticker: chain.ticker,
            logo: chain.logo,
            tokenChainLogo: nil,
            isSelected: Binding(get: {
                viewModel.isSelected(chain: chain)
            }, set: {
                viewModel.toggleSelection(chain: chain, isSelected: $0)
            })
        ) {}
    }
}

#Preview {
    KeyImportCustomizeChainsView(
        viewModel: KeyImportChainsSetupViewModel(),
        onImport: {}
    )
}
