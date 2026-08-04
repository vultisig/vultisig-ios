//
//  DefiChainSelectPositionsScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/10/2025.
//

import OSLog
import SwiftUI

private let logger = Log.defi.view

struct DefiChainSelectPositionsScreen: View {
    @ObservedObject var viewModel: DefiChainMainViewModel
    @Binding var isPresented: Bool

    /// Coin buckets, one per `DefiPositions` field. Deliberately `[[CoinMeta]]`
    /// and not the picker's element type: `onSave` hands everything in here to
    /// `CoinService.addToChain`, so nothing that must not become a wallet coin
    /// can be stored in it.
    @State var selection: [[CoinMeta]] = []
    /// Kamino vault addresses the user has turned on. Persisted onto
    /// `KaminoPosition.isEnabled` rather than into a `DefiPositions` bucket.
    @State var earnSelection: Set<String> = []
    @State var isLoading: Bool = false

    private let kaminoStorage = KaminoPositionStorageService()

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
                emptyStateBuilder: { PositionNotFoundEmptyStateView() },
                onRetrySection: { _ in viewModel.loadLiquidityPools() }
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
    func cellBuilder(_ asset: DefiSelectableAsset, section: DefiChainPositionType) -> some View {
        switch asset {
        case .coin(let coin):
            coinCell(coin, section: section)
        case .kaminoVault(let descriptor):
            KaminoVaultSelectionGridCell(
                descriptor: descriptor,
                isSelected: earnSelection.contains(descriptor.address)
            ) { selected in
                if selected {
                    earnSelection.insert(descriptor.address)
                } else {
                    earnSelection.remove(descriptor.address)
                }
            }
        }
    }

    @ViewBuilder
    func coinCell(_ asset: CoinMeta, section: DefiChainPositionType) -> some View {
        let pos = section.selectionIndex
        TokenSelectionGridCell(
            coin: asset,
            // Prefix for LPs
            name: section == .liquidityPool ? "\(viewModel.chain.ticker)/\(asset.ticker)" : asset.ticker,
            showChainIcon: section == .liquidityPool,
            isSelected: pos.flatMap { selection[safe: $0]?.contains(asset) } ?? false
        ) { selected in
            guard let pos else { return }
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
        earnSelection = kaminoStorage.enabledVaultAddresses(for: viewModel.vault)
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
            updateKaminoPositions()

            // Only ever the coin buckets: `selection` cannot hold a Kamino
            // vault, so no vault can be added to the wallet as a token.
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
        // CTA immediately (zero amount) — the next refresh updates the amount. Solana is skipped:
        // its rows are per-stake-account and discovered on-chain (`upsert(solanaStake:for:)`),
        // so a coin-keyed zero row would alias every account onto one id, and its segment
        // renders the total card + Delegate CTA without needing a placeholder row.
        let storage = DefiPositionsStorageService()
        for added in newStaking.subtracting(previousStaking) where added.chain != .solana {
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

    /// Mirrors the Earn selection onto `KaminoPosition.isEnabled`, in one save,
    /// so a failure cannot leave half of it applied. Disabling keeps the row and
    /// its snapshot and only clears the flag, because disabling a vault does not
    /// withdraw from it.
    @MainActor
    func updateKaminoPositions() {
        // The Earn section is only ever offered on the vaults' own chain. Without
        // this gate, saving the picker on any other chain would see an empty
        // `earnSelection` and switch every enabled vault off.
        guard viewModel.chain == KaminoVaultRegistry.chain else { return }
        do {
            try kaminoStorage.setEnabledVaults(earnSelection, for: viewModel.vault)
        } catch {
            logger.error("Failed to update Kamino positions: \(error.localizedDescription, privacy: .private)")
        }
    }
}

/// Grid cell for a curated Kamino vault. Carries the vault's own name and its
/// underlying token's artwork — the vault is what the user picks, the token is
/// what they recognise.
private struct KaminoVaultSelectionGridCell: View {
    let descriptor: KaminoVaultDescriptor
    var onSelection: (Bool) -> Void

    @State private var isSelected: Bool

    init(
        descriptor: KaminoVaultDescriptor,
        isSelected: Bool,
        onSelection: @escaping (Bool) -> Void
    ) {
        self.descriptor = descriptor
        self.onSelection = onSelection
        self._isSelected = State(initialValue: isSelected)
    }

    var body: some View {
        let coin = descriptor.underlyingCoinMeta
        AssetSelectionGridCell(
            name: descriptor.fallbackName,
            ticker: coin?.ticker ?? descriptor.fallbackName,
            logo: coin?.logo ?? "",
            isSelected: $isSelected
        ) {
            onSelection(isSelected)
        }
    }
}

private struct PositionNotFoundEmptyStateView: View {
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                Icon(.circleDashed, color: Theme.colors.primaryAccent4, size: 24)
                Text("noPositionsFound")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(Theme.radius.xl.shape.fill(Theme.colors.bgSurface1))
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
