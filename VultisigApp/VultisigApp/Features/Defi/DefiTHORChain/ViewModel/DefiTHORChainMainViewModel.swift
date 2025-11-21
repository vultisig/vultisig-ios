//
//  DefiTHORChainMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation
import SwiftUI

final class DefiTHORChainMainViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published var selectedPosition: THORChainPositionType = .bond
    private(set) lazy var positions: [SegmentedControlItem<THORChainPositionType>] = THORChainPositionType.allCases.map { SegmentedControlItem(value: $0, title: $0.segmentedControlTitle) }
    
    @Published private(set) var availablePositions: [AssetSection<THORChainPositionType, CoinMeta>] = []
    @Published var positionsSearchText = ""
    
    private let logic = DefiTHORChainMainLogic()
    
    var filteredAvailablePositions: [AssetSection<THORChainPositionType, CoinMeta>] {
        return logic.filteredAvailablePositions(
            positionsSearchText: positionsSearchText,
            availablePositions: availablePositions
        )
    }
    
    init(vault: Vault) {
        self.vault = vault
    }
    
    func update(vault: Vault) {
        self.vault = vault
    }
    
    func moveToNextPosition() {
        selectedPosition = logic.getNextPosition(current: selectedPosition)
    }
    
    func moveToPreviousPosition() {
        selectedPosition = logic.getPreviousPosition(current: selectedPosition)
    }
    
    func onLoad() {
        Task {
            await setupThorchainPositions()
        }
    }
    
    func refresh() async {
        guard let runeCoin = vault.runeCoin else {
            return
        }

        await BalanceService.shared.updateBalance(for: runeCoin)
    }
    
    func setupThorchainPositions() async {
        let positions = await logic.fetchThorchainPositions()
        await MainActor.run {
            availablePositions = positions
        }
    }
}

struct DefiTHORChainMainLogic {
    
    private let thorchainService = THORChainAPIService()
    private let positionsService = DefiPositionsService()
    
    func filteredAvailablePositions(
        positionsSearchText: String,
        availablePositions: [AssetSection<THORChainPositionType, CoinMeta>]
    ) -> [AssetSection<THORChainPositionType, CoinMeta>] {
        guard positionsSearchText.isNotEmpty else { return availablePositions }
        return availablePositions.compactMap { section in
            let newPositions = section.assets
                .filter { $0.ticker.localizedCaseInsensitiveContains(positionsSearchText) || $0.chain.ticker.localizedCaseInsensitiveContains(positionsSearchText) }
            guard !newPositions.isEmpty else { return nil }
            return AssetSection(title: section.title, type: section.type, assets: newPositions)
        }
    }
    
    func getNextPosition(current: THORChainPositionType) -> THORChainPositionType {
        let allPositions = THORChainPositionType.allCases
        let currentIndex = allPositions.firstIndex(of: current) ?? 0
        let nextIndex = (currentIndex + 1) % allPositions.count
        return allPositions[nextIndex]
    }
    
    func getPreviousPosition(current: THORChainPositionType) -> THORChainPositionType {
        let allPositions = THORChainPositionType.allCases
        let currentIndex = allPositions.firstIndex(of: current) ?? 0
        let previousIndex = currentIndex == 0 ? allPositions.count - 1 : currentIndex - 1
        return allPositions[previousIndex]
    }
    
    func fetchThorchainPositions() async -> [AssetSection<THORChainPositionType, CoinMeta>] {
        let bond = positionsService.bondCoins(for: .thorChain)
        let staking = positionsService.stakeCoins(for: .thorChain)
        let pools = (try? await thorchainService.getPools()) ?? []
        let lps = pools.compactMap { THORChainAssetFactory.createCoin(from: $0.asset) }
        
        return [
            AssetSection(title: THORChainPositionType.bond.sectionTitle, type: THORChainPositionType.bond, assets: bond),
            AssetSection(title: THORChainPositionType.stake.sectionTitle, type: .stake, assets: staking),
            AssetSection(title: THORChainPositionType.liquidityPool.sectionTitle, type: .liquidityPool, assets: lps)
        ]
    }
}
