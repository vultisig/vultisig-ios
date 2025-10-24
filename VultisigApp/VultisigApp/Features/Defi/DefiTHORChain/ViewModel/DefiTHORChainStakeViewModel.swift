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

    var hasStakePositions: Bool {
        !stakePositions.isEmpty
    }

    var vaultStakePositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []
    }

    private let thorchainAPIService = THORChainAPIService()

    init(vault: Vault) {
        self.vault = vault
        loadStakePositions()
    }

    func update(vault: Vault) {
        self.vault = vault
        loadStakePositions()
    }

    func refresh() async {
        loadStakePositions()
    }

    private func loadStakePositions() {
        stakePositions = vaultStakePositions.compactMap { coinMeta -> StakePosition? in
            guard let coin = vault.coins.first(where: { $0.ticker == coinMeta.ticker && $0.chain == coinMeta.chain }) else {
                return nil
            }

            return createStakePosition(for: coin, coinMeta: coinMeta)
        }
        .sorted { $0.amount > $1.amount }
    }

    private func createStakePosition(for coin: Coin, coinMeta: CoinMeta) -> StakePosition {
        let ticker = coin.ticker.uppercased()

        switch ticker {
        case "TCY":
            // TODO: Fetch APR from API
            return StakePosition(
                coin: coinMeta,
                type: .stake,
                amount: coin.stakedBalanceDecimal,
                apr: nil, // TODO: Fill with actual APR
                estimatedReward: nil, // TODO: Fill with actual estimated reward
                nextPayout: nil, // TODO: Fill with actual next payout
                rewards: nil, // TCY doesn't generate rewards
                rewardCoin: nil
            )

        case "RUJI":
            // TODO: Fetch APR from API
            return StakePosition(
                coin: coinMeta,
                type: .stake,
                amount: coin.stakedBalanceDecimal,
                apr: nil, // TODO: Fill with actual APR
                estimatedReward: nil,
                nextPayout: nil,
                rewards: nil, // RUJI doesn't generate rewards
                rewardCoin: nil
            )

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
