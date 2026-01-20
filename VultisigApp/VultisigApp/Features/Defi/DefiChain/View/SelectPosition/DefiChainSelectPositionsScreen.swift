//
//  DefiChainSelectPositionsScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/10/2025.
//

import SwiftUI

struct DefiChainSelectPositionsScreen: View {
    @ObservedObject var viewModel: DefiChainMainViewModel
    @Binding var isPresented: Bool
    
    @State var selection: [[CoinMeta]] = []
    @State var isLoading: Bool = false
    
    var body: some View {
        ZStack {
            AssetSelectionContainerSheet(
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
            .withLoading(isLoading: $isLoading)
        }
        .onAppear {
            setupSelection()
        }
        .onDisappear {
            viewModel.positionsSearchText = ""
        }
    }
    
    @ViewBuilder
    func cellBuilder(_ asset: CoinMeta, section: DefiChainPositionType) -> some View {
        let pos = viewModel.availablePositions.firstIndex(where: { $0.type == section }) ?? 0
        TokenSelectionGridCell(
            coin: asset,
            // Prefix for LPs
            name: section == .liquidityPool ? "\(viewModel.chain.ticker)/\(asset.ticker)" : asset.ticker,
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
        let defiPositions = viewModel.vault.defiPositions.first { $0.chain == viewModel.chain }
        selection = [
            defiPositions?.bonds ?? [],
            defiPositions?.staking ?? [],
            defiPositions?.lps ?? []
        ]
    }
    
    func add(asset: CoinMeta, section: Int) {
        guard selection.indices.contains(section) else { return }
        selection[section] = selection[section] + [asset]
    }
    
    func remove(asset: CoinMeta, section: Int) {
        guard selection.indices.contains(section) else { return }
        selection[section] = selection[section].filter { $0 != asset }
    }
    
    func onSave() {
        Task {
            isLoading = true
            updateVaultDefiPositions()
            
            let vaultCoins = viewModel.vault.coins.map { $0.toCoinMeta() }
            let filteredDefiCoins = Set(selection.flatMap { $0 }).filter {
                !vaultCoins.contains($0)
            }
            
            try? await CoinService.addToChain(assets: Array(filteredDefiCoins), to: viewModel.vault)
            isLoading = false
            isPresented = false
        }
    }
    
    @MainActor
    func updateVaultDefiPositions() {
        viewModel.vault.defiPositions.removeAll(where: { $0.chain == viewModel.chain })
        viewModel.vault.defiPositions.append(
            DefiPositions(
                chain: viewModel.chain,
                bonds: Array(Set(selection[safe: 0] ?? [])),
                staking: Array(Set(selection[safe: 1] ?? [])),
                lps: Array(Set(selection[safe: 2] ?? []))
            )
        )
        
        try? Storage.shared.save()
    }
}

#Preview {
    DefiChainSelectPositionsScreen(
        viewModel: DefiChainMainViewModel(vault: .example, chain: .thorChain),
        isPresented: .constant(true)
    )
}
