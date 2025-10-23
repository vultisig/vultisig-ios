//
//  DefiTHORChainSelectPositionsScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/10/2025.
//

import SwiftUI

struct DefiTHORChainSelectPositionsScreen: View {
    @ObservedObject var viewModel: DefiTHORChainMainViewModel
    @Binding var isPresented: Bool
    
    @State var selection: [[CoinMeta]] = []
    
    var body: some View {
        ZStack {
            AssetSelectionContainerScreen(
                title: "selectPositions".localized,
                subtitle: "selectPositionsSubtitle".localized,
                isPresented: $isPresented,
                searchText: $viewModel.positionsSearchText,
                elements: viewModel.filteredAvailablePositions,
                onSave: onSave,
                cellBuilder: cellBuilder,
                emptyStateBuilder: { EmptyView() }
            )
            .showIf(!selection.isEmpty)
        }
        .onAppear {
            setupSelection()
        }
        .onDisappear {
            viewModel.positionsSearchText = ""
        }
    }
    
    @ViewBuilder
    func cellBuilder(_ asset: CoinMeta, section: THORChainPositionType) -> some View {
        let pos = viewModel.availablePositions.firstIndex(where: { $0.type == section }) ?? 0
        TokenSelectionGridCell(
            coin: asset,
            // Prefix for LPs
            name: section == .liquidityPool ? "RUNE/\(asset.ticker)" : asset.ticker,
            showChainIcon: section == .liquidityPool,
            isSelected: selection[safe: pos]?.contains(asset) ?? false
        ) { selected in
            if selected {
                add(asset: asset, section: pos)
            } else {
                remove(asset: asset, section: pos)
            }
        }
    }
    
    func setupSelection() {
        let defiPositions = viewModel.vault.defiPositions.first { $0.chain == .thorChain }
        selection = [
            defiPositions?.bonds ?? [],
            defiPositions?.staking ?? [],
            defiPositions?.lps ?? [],
        ]
    }
    
    func add(asset: CoinMeta, section: Int) {
        selection[section] = selection[section] + [asset]
    }
    
    func remove(asset: CoinMeta, section: Int) {
        selection[section] = selection[section].filter { $0 != asset }
    }
    
    func onSave() {
        Task {
            updateVaultDefiPositions()
            await MainActor.run { isPresented = false }
        }
    }
    
    @MainActor
    func updateVaultDefiPositions() {
        viewModel.vault.defiPositions.removeAll(where: { $0.chain == .thorChain })
        viewModel.vault.defiPositions.append(
            DefiPositions(
                chain: .thorChain,
                bonds: Array(Set(selection[safe: 0] ?? [])),
                staking: Array(Set(selection[safe: 1] ?? [])),
                lps: Array(Set(selection[safe: 2] ?? []))
            )
        )
        
        try? Storage.shared.save()
    }
}

#Preview {
    DefiTHORChainSelectPositionsScreen(
        viewModel: DefiTHORChainMainViewModel(vault: .example),
        isPresented: .constant(true)
    )
}
