//
//  DefiChainSelectPositionsScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/10/2025.
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-chain-select-positions")

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
                emptyStateBuilder: { PositionNotFoundEmptyStateView() }
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
        let chain = viewModel.chain
        let vault = viewModel.vault

        let previous = vault.defiPositions.first { $0.chain == chain }
        let previousStaking = Set(previous?.staking ?? [])
        let previousLps = Set(previous?.lps ?? [])
        let newStaking = Set(selection[safe: 1] ?? [])
        let newLps = Set(selection[safe: 2] ?? [])

        vault.defiPositions.removeAll { $0.chain == chain }
        vault.defiPositions.append(
            DefiPositions(
                chain: chain,
                bonds: Array(Set(selection[safe: 0] ?? [])),
                staking: Array(newStaking),
                lps: Array(newLps)
            )
        )

        do {
            try Storage.shared.save()
        } catch {
            logger.error("Failed to save vault defi positions: \(error.localizedDescription, privacy: .private)")
        }

        // Mirror the enable/disable into persisted position rows so the user sees a row with its
        // CTA immediately (zero amount) — the next refresh updates the amount.
        let storage = DefiPositionsStorageService()
        for added in newStaking.subtracting(previousStaking) {
            do {
                try storage.addZero(stakeCoin: added, to: vault)
            } catch {
                logger.error("Failed to add zero stake row for \(added.ticker, privacy: .public): \(error.localizedDescription, privacy: .private)")
            }
        }
        for removed in previousStaking.subtracting(newStaking) {
            do {
                try storage.removeStake(coin: removed, from: vault)
            } catch {
                logger.error("Failed to remove stake row for \(removed.ticker, privacy: .public): \(error.localizedDescription, privacy: .private)")
            }
        }
        if let nativeCoin = vault.nativeCoin(for: chain)?.toCoinMeta() {
            for added in newLps.subtracting(previousLps) {
                do {
                    try storage.addZero(lpCoin2: added, nativeCoin: nativeCoin, to: vault)
                } catch {
                    logger.error("Failed to add zero LP row for \(added.ticker, privacy: .public): \(error.localizedDescription, privacy: .private)")
                }
            }
        }
        for removed in previousLps.subtracting(newLps) {
            do {
                try storage.removeLP(coin2: removed, from: vault)
            } catch {
                logger.error("Failed to remove LP row for \(removed.ticker, privacy: .public): \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}

private struct PositionNotFoundEmptyStateView: View {
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                Icon(named: "crypto", color: Theme.colors.primaryAccent4, size: 24)
                Text("noPositionsFound")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface1))
            Spacer()
        }
    }
}

#Preview {
    DefiChainSelectPositionsScreen(
        viewModel: DefiChainMainViewModel(vault: .example, chain: .thorChain),
        isPresented: .constant(true)
    )
}
