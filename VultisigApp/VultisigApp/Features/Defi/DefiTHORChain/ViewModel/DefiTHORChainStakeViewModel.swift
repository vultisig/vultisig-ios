//
//  DefiTHORChainStakeViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import SwiftUI
import BigInt
import VultisigCommonData

final class DefiTHORChainStakeViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var stakePositions: [StakePosition] = []
    @Published private(set) var initialLoadingDone: Bool = false

    private let logic = DefiTHORChainStakeLogic()

    var hasStakePositions: Bool {
        !stakePositions.isEmpty
    }

    var vaultStakePositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []
    }

    init(vault: Vault) {
        self.vault = vault
        Task {
            await loadStakePositions()
        }
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func refresh() async {
        await loadStakePositions()
    }
    
    @MainActor
    private func loadStakePositions() async {
        guard vault.runeCoin != nil else {
            print("Error: RUNE coin not found in vault for price lookups")
            initialLoadingDone = true
            return
        }
        
        // Initial fast load from vault
        let cachedPositions = vault.stakePositions
            .filter { vaultStakePositions.contains($0.coin) }
            .sorted { $0.amount > $1.amount }
        
        if !cachedPositions.isEmpty {
            stakePositions = cachedPositions
            initialLoadingDone = true
        }
        
        let positions = await logic.loadStakePositions(vault: vault, vaultStakePositions: vaultStakePositions)
        
        stakePositions = positions
        initialLoadingDone = true
    }
}

struct DefiTHORChainStakeLogic {
    
    private let thorchainAPIService = THORChainAPIService()
    private let stakingService = THORChainStakingService.shared
    private let positionsStorageService = DefiPositionsStorageService()
    
    func loadStakePositions(vault: Vault, vaultStakePositions: [CoinMeta]) async -> [StakePosition] {
        guard let runeCoin = vault.runeCoin else {
            print("Error: RUNE coin not found in vault for price lookups")
            return []
        }
        
        var positions: [StakePosition] = []
        for coinMeta in vaultStakePositions {
            guard let coin = vault.coins.first(where: { $0.ticker == coinMeta.ticker && $0.chain == coinMeta.chain }) else {
                continue
            }

            if let position = await createStakePosition(for: coin, runeCoin: runeCoin, coinMeta: coinMeta, vault: vault) {
                positions.append(position)
            }
        }

        let sortedPositions = positions.sorted { $0.amount > $1.amount }
        await savePositions(positions: sortedPositions)
        return sortedPositions
    }
    
    private func createStakePosition(for coin: Coin, runeCoin: Coin, coinMeta: CoinMeta, vault: Vault) async -> StakePosition? {
        let ticker = coin.ticker.uppercased()
        switch ticker {
        case "TCY", "RUJI":
            do {
                let details = try await stakingService.fetchStakingDetails(
                    coin: coin,
                    runeCoin: runeCoin,
                    address: coin.address
                )

                return StakePosition(
                    coin: coinMeta,
                    type: .stake,
                    amount: details.stakedAmount,
                    apr: details.apr,
                    estimatedReward: details.estimatedReward,
                    nextPayout: details.nextPayoutDate,
                    rewards: details.rewards,
                    rewardCoin: details.rewardsCoin,
                    vault: vault
                )
            } catch {
                print("Error fetching \(ticker) staking details: \(error.localizedDescription)")
                // Fallback to using local staked balance
                return StakePosition(
                    coin: coinMeta,
                    type: .stake,
                    amount: coin.stakedBalanceDecimal,
                    apr: nil,
                    estimatedReward: nil,
                    nextPayout: nil,
                    rewards: nil,
                    rewardCoin: nil,
                    vault: vault
                )
            }

        case "YRUNE", "YTCY":
            return StakePosition(
                coin: coinMeta,
                type: .index,
                amount: coin.balanceDecimal,
                apr: nil,
                estimatedReward: nil,
                nextPayout: nil,
                rewards: nil,
                rewardCoin: nil,
                vault: vault
            )
        default:
            // Default case for other stake positions
            return StakePosition(
                coin: coinMeta,
                type: .stake,
                amount: coin.stakedBalanceDecimal,
                apr: nil,
                estimatedReward: nil,
                nextPayout: nil,
                rewards: nil,
                rewardCoin: nil,
                vault: vault
            )
        }
    }
    
    @MainActor
    private func savePositions(positions: [StakePosition]) async {
        do {
            try positionsStorageService.upsert(positions)
        } catch {
            print("An error occured while saving staked positions: \(error)")
        }
    }
}
