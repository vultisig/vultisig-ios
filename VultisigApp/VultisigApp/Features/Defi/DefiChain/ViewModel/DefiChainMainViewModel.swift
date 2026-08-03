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

    @Published private(set) var availablePositions: [AssetSection<DefiChainPositionType, CoinMeta>] = []
    @Published var positionsSearchText = ""

    var filteredAvailablePositions: [AssetSection<DefiChainPositionType, CoinMeta>] {
        guard positionsSearchText.isNotEmpty else { return availablePositions }
        return availablePositions.compactMap { section in
            let newPositions = section.assets
                .filter { $0.ticker.localizedCaseInsensitiveContains(positionsSearchText) || $0.chain.ticker.localizedCaseInsensitiveContains(positionsSearchText) }
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

    /// Publishes the whole catalog synchronously. Bond and stake come from
    /// static in-app lists and must never wait on the network — gating them on
    /// the pool fetch left the picker rendering its "no positions" empty state
    /// for the duration of the request, with nothing to enable.
    ///
    /// All three sections are always present and always in this order: the
    /// picker maps a tapped cell back to a selection bucket by section type, and
    /// the persisted `DefiPositions` record has one field per type.
    func setupSelectablePositions() {
        let supportsLiquidityPools = positionsService.supportsLiquidityPools(for: chain)
        availablePositions = [
            AssetSection(
                title: DefiChainPositionType.bond.sectionTitle,
                type: .bond,
                assets: positionsService.bondCoins(for: chain)
            ),
            AssetSection(
                title: DefiChainPositionType.stake.sectionTitle,
                type: .stake,
                assets: positionsService.stakeCoins(for: chain)
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
            assets: assets,
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
            // Solana native (Stake program) staking only — routes to
            // `SolanaStakeDefiView` (see `DefiChainMainScreen.solanaStakeView`).
            [.stake]
        default:
            []
        }
    }
}
