//
//  DefiTHORChainStakeViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

final class DefiTHORChainStakeViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var stakePositions: [StakePosition] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var setupDone: Bool = false

    var hasStakePositions: Bool {
        !stakePositions.isEmpty
    }

    var vaultStakePositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []
    }

    private let thorchainAPIService = THORChainAPIService()
    private let stakingService = THORChainStakingService.shared

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
        guard let runeCoin = vault.coins.first(where: { $0.ticker == "RUNE" && $0.chain == .thorChain }) else {
            print("Error: RUNE coin not found in vault for price lookups")
            setupDone = true
            return
        }
        
        isLoading = true
        var positions: [StakePosition] = []
        for coinMeta in vaultStakePositions {
            guard let coin = vault.coins.first(where: { $0.ticker == coinMeta.ticker && $0.chain == coinMeta.chain }) else {
                continue
            }

            if let position = await createStakePosition(for: coin, runeCoin: runeCoin, coinMeta: coinMeta) {
                positions.append(position)
            }
        }

        stakePositions = positions.sorted { $0.amount > $1.amount }
        isLoading = false
        setupDone = true
    }

    private func createStakePosition(for coin: Coin, runeCoin: Coin, coinMeta: CoinMeta) async -> StakePosition? {
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
                    rewardCoin: details.rewardsCoin
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
                    rewardCoin: nil
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
                rewardCoin: nil
            )

        case "STCY":
            return StakePosition(
                coin: coinMeta,
                type: .compound,
                amount: coin.balanceDecimal,
                apr: nil,
                estimatedReward: nil,
                nextPayout: nil,
                rewards: nil,
                rewardCoin: nil
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
                rewardCoin: nil
            )
        }
    }
}
