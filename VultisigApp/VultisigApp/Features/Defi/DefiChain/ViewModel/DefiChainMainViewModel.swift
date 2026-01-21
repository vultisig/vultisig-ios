//
//  DefiChainMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation

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
            return AssetSection(title: section.title, type: section.type, assets: newPositions)
        }
    }

    let chain: Chain

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func moveToNextPosition() {
        let allPositions = DefiChainPositionType.allCases
        let currentIndex = allPositions.firstIndex(of: selectedPosition) ?? 0
        let nextIndex = (currentIndex + 1) % allPositions.count
        selectedPosition = allPositions[nextIndex]
    }

    func moveToPreviousPosition() {
        let allPositions = DefiChainPositionType.allCases
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
        Task {
            await setupSelectablePositions()
        }
    }

    func refresh() async {
        guard let nativeCoin = vault.nativeCoin(for: chain) else { return }
        await BalanceService.shared.updateBalance(for: nativeCoin)
    }

    func setupSelectablePositions() async {
        let positionsService = DefiPositionsService()
        let bond = positionsService.bondCoins(for: chain)
        let staking = positionsService.stakeCoins(for: chain)
        let lps = await positionsService.lpCoins(for: chain)

        await MainActor.run {
            availablePositions = [
                AssetSection(title: DefiChainPositionType.bond.sectionTitle, type: DefiChainPositionType.bond, assets: bond),
                AssetSection(title: DefiChainPositionType.stake.sectionTitle, type: .stake, assets: staking),
                AssetSection(title: DefiChainPositionType.liquidityPool.sectionTitle, type: .liquidityPool, assets: lps)
            ]
        }
    }

    func getDefiPositionTypes() -> [DefiChainPositionType] {
        switch chain {
        case .thorChain:
            [.bond, .stake, .liquidityPool]
        case .mayaChain:
            [.bond, .stake, .liquidityPool]
        default:
            []
        }
    }
}
