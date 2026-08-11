//
//  DefiChainMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation
import OSLog

private let logger = Log.defi.viewModel

@MainActor
final class DefiChainMainViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published var selectedPosition: DefiChainPositionType = .bond
    @Published var positions: [SegmentedControlItem<DefiChainPositionType>] = []

    @Published private(set) var availablePositions: [AssetSection<DefiChainPositionType, DefiSelectableAsset>] = []
    @Published var positionsSearchText = ""

    var filteredAvailablePositions: [AssetSection<DefiChainPositionType, DefiSelectableAsset>] {
        guard positionsSearchText.isNotEmpty else { return availablePositions }
        return availablePositions.compactMap { section in
            // An unresolved section has nothing to match yet. Keep it so a search
            // run while the pool list is still arriving doesn't claim "no
            // positions found", and so a failed section keeps its retry action.
            guard section.state == .loaded else { return section }
            let newPositions = section.assets
                .filter { asset in
                    asset.searchTerms.contains { $0.localizedCaseInsensitiveContains(positionsSearchText) }
                }
            guard !newPositions.isEmpty else { return nil }
            return AssetSection(title: section.title, type: section.type, assets: newPositions, state: section.state)
        }
    }

    let chain: Chain

    private let positionsService: DefiPositionsProviding
    /// Wall-clock cap on the liquidity-pool fetch, so the section cannot sit in
    /// its loading state indefinitely behind a stalled connection.
    private let lpLoadTimeout: TimeInterval
    /// Readable so tests can await the in-flight fetch instead of polling.
    private(set) var lpLoadTask: Task<Void, Never>?

    init(
        vault: Vault,
        chain: Chain,
        positionsService: DefiPositionsProviding = DefiPositionsService(),
        lpLoadTimeout: TimeInterval = 15
    ) {
        self.vault = vault
        self.chain = chain
        self.positionsService = positionsService
        self.lpLoadTimeout = lpLoadTimeout
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func moveToNextPosition() {
        let allPositions = positions.map(\.value)
        guard !allPositions.isEmpty else { return }
        let currentIndex = allPositions.firstIndex(of: selectedPosition) ?? 0
        let nextIndex = (currentIndex + 1) % allPositions.count
        selectedPosition = allPositions[nextIndex]
    }

    func moveToPreviousPosition() {
        let allPositions = positions.map(\.value)
        guard !allPositions.isEmpty else { return }
        let currentIndex = allPositions.firstIndex(of: selectedPosition) ?? 0
        let previousIndex = currentIndex == 0 ? allPositions.count - 1 : currentIndex - 1
        selectedPosition = allPositions[previousIndex]
    }

    func onLoad() {
        let positionTypes = getDefiPositionTypes()
        positions = positionTypes.map {
            SegmentedControlItem(value: $0, title: $0.segmentedControlTitle)
        }
        selectedPosition = positionTypes.first ?? .bond
        setupSelectablePositions()
    }

    func refresh() async {
        guard let nativeCoin = vault.nativeCoin(for: chain) else { return }
        await BalanceService.shared.updateBalance(for: nativeCoin)
    }

    /// Publishes the whole catalog synchronously. Bond, stake and earn come from
    /// static in-app lists and must never wait on the network — gating them on
    /// the pool fetch left the picker rendering its "no positions" empty state
    /// for the duration of the request, with nothing to enable.
    ///
    /// The first three sections are always present and always in this order: the
    /// picker maps a tapped cell back to a selection bucket by section type, and
    /// the persisted `DefiPositions` record has one field per type. Earn is
    /// appended only on the chain that has yield vaults, and is deliberately
    /// last — it has no `DefiPositions` bucket at all (its enablement lives on
    /// `KaminoPosition`), so it can neither shift nor claim one of the three.
    func setupSelectablePositions() {
        let supportsLiquidityPools = positionsService.supportsLiquidityPools(for: chain)
        var sections: [AssetSection<DefiChainPositionType, DefiSelectableAsset>] = [
            AssetSection(
                title: DefiChainPositionType.bond.sectionTitle,
                type: .bond,
                assets: positionsService.bondCoins(for: chain).map { .coin($0) }
            ),
            AssetSection(
                title: DefiChainPositionType.stake.sectionTitle,
                type: .stake,
                assets: positionsService.stakeCoins(for: chain).map { .coin($0) }
            ),
            AssetSection(
                title: DefiChainPositionType.liquidityPool.sectionTitle,
                type: .liquidityPool,
                assets: [],
                // A chain without pools resolves to a genuine empty section, not
                // a spinner that would never finish.
                state: supportsLiquidityPools ? .loading : .loaded
            )
        ]

        let earnVaults = positionsService.earnVaults(for: chain)
        if !earnVaults.isEmpty {
            sections.append(
                AssetSection(
                    title: DefiChainPositionType.earn.sectionTitle,
                    type: .earn,
                    assets: earnVaults.map { .kaminoVault($0) }
                )
            )
        }
        availablePositions = sections

        guard supportsLiquidityPools else { return }
        loadLiquidityPools()
    }

    /// Fetches the liquidity-pool catalog independently of the static sections.
    /// A failure or timeout only marks the LP section `.failed` — the bond and
    /// stake sections stay exactly as they are.
    func loadLiquidityPools() {
        lpLoadTask?.cancel()
        updateLiquidityPoolSection(assets: [], state: .loading)

        lpLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let lps = try await withTimeout(seconds: self.lpLoadTimeout) { [positionsService = self.positionsService, chain = self.chain] in
                    try await positionsService.lpCoins(for: chain)
                }
                guard !Task.isCancelled else { return }
                self.updateLiquidityPoolSection(assets: lps, state: .loaded)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to load \(self.chain.rawValue, privacy: .public) LP catalog: \(error.localizedDescription, privacy: .public)")
                self.updateLiquidityPoolSection(assets: [], state: .failed(message: "failedToLoadPools".localized))
            }
        }
    }

    /// Replaces the LP section in place so the section order — which the picker
    /// depends on — is never disturbed.
    private func updateLiquidityPoolSection(assets: [CoinMeta], state: AssetSectionState) {
        guard let index = availablePositions.firstIndex(where: { $0.type == .liquidityPool }) else { return }
        let section = availablePositions[index]
        availablePositions[index] = AssetSection(
            title: section.title,
            type: section.type,
            assets: assets.map { .coin($0) },
            state: state
        )
    }

    func getDefiPositionTypes() -> [DefiChainPositionType] {
        switch chain {
        case .thorChain:
            [.bond, .stake, .liquidityPool]
        case .mayaChain:
            [.bond, .stake, .liquidityPool]
        case .terra, .terraClassic:
            // Stake-only segment for Cosmos-SDK staking on LUNA / LUNC.
            // These chains route to `CosmosStakeDefiView` (see
            // `DefiChainMainScreen.cosmosStakeView`); the polished
            // position-card UI lands in a follow-up.
            [.stake]
        case .qbtc:
            // QBTC adds an in-app governance proposals segment alongside
            // staking. Governance is not a selectable asset, so it is
            // always present here and skips `setupSelectablePositions()`.
            [.stake, .governance]
        case .ton:
            // TON nominator-pool staking only — no bond / LP segments.
            [.stake]
        case .solana:
            // Kamino Earn yield vaults first, then native (Stake program)
            // staking — routed to `KaminoEarnView` and `SolanaStakeDefiView`
            // respectively (see `DefiChainMainScreen`).
            //
            // Earn leads, which also makes it the segment the screen opens on:
            // `onLoad` selects the first type. That is what the design asks for,
            // and the order here is presentational only — the picker files a
            // selection by `selectionIndex`, which Earn does not have at all.
            [.earn, .stake]
        default:
            []
        }
    }
}
