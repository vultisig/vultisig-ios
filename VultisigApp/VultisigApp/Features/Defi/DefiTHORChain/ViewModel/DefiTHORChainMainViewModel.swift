//
//  DefiTHORChainMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation

final class DefiTHORChainMainViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published var selectedPosition: THORChainPositionType = .bond
    private(set) lazy var positions: [SegmentedControlItem<THORChainPositionType>] = THORChainPositionType.allCases.map { SegmentedControlItem(value: $0, title: $0.segmentedControlTitle) }
    
    @Published private(set) var availablePositions: [AssetSection<THORChainPositionType, CoinMeta>] = []
    @Published var positionsSearchText = ""
    
    var filteredAvailablePositions: [AssetSection<THORChainPositionType, CoinMeta>] {
        guard positionsSearchText.isNotEmpty else { return availablePositions }
        return availablePositions.compactMap { section in
            let newPositions = section.assets
                .filter { $0.ticker.localizedCaseInsensitiveContains(positionsSearchText) || $0.chain.ticker.localizedCaseInsensitiveContains(positionsSearchText) }
            guard !newPositions.isEmpty else { return nil }
            return AssetSection(title: section.title, type: section.type, assets: newPositions)
        }
    }
    
    private let thorchainService = THORChainAPIService()
    
    init(vault: Vault) {
        self.vault = vault
    }
    
    func update(vault: Vault) {
        self.vault = vault
    }
    
    func moveToNextPosition() {
        let allPositions = THORChainPositionType.allCases
        let currentIndex = allPositions.firstIndex(of: selectedPosition) ?? 0
        let nextIndex = (currentIndex + 1) % allPositions.count
        selectedPosition = allPositions[nextIndex]
    }
    
    func moveToPreviousPosition() {
        let allPositions = THORChainPositionType.allCases
        let currentIndex = allPositions.firstIndex(of: selectedPosition) ?? 0
        let previousIndex = currentIndex == 0 ? allPositions.count - 1 : currentIndex - 1
        selectedPosition = allPositions[previousIndex]
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
        let bond = [TokensStore.rune]
        let staking = [
            TokensStore.tcy,
            TokensStore.ruji,
            TokensStore.stcy,
            TokensStore.yrune,
            TokensStore.ytcy
        ]
        let pools = (try? await thorchainService.getPools()) ?? []
        let lps = pools.compactMap { THORChainAssetFactory.createCoin(from: $0.asset) }
        
        await MainActor.run {
            availablePositions = [
                AssetSection(title: THORChainPositionType.bond.sectionTitle, type: THORChainPositionType.bond, assets: bond),
                AssetSection(title: THORChainPositionType.stake.sectionTitle, type: .stake, assets: staking),
                AssetSection(title: THORChainPositionType.liquidityPool.sectionTitle, type: .liquidityPool, assets: lps)
            ]
        }
    }
}
