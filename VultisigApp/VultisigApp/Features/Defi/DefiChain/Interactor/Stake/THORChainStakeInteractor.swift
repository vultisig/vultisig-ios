//
//  THORChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

struct THORChainStakeInteractor: StakeInteractor {
    private let thorchainAPIService = THORChainAPIService()
    private let stakingService = THORChainStakingService.shared

    func fetchStakePositions(vault: Vault) async -> [StakePosition] {
        // Snapshot SwiftData @Model fields before any await to avoid MainActor violations
        let runeCoin = vault.runeCoin
        let vaultStakePositions = vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []
        let vaultCoins = vault.coins

        var apiPositions: [StakePosition] = []
        var fallbackPositions: [StakePosition] = []

        for coinMeta in vaultStakePositions {
            guard let coin = vaultCoins.first(where: { $0.ticker == coinMeta.ticker && $0.chain == coinMeta.chain }) else {
                continue
            }

            let result = await createStakePosition(for: coin, runeCoin: runeCoin, coinMeta: coinMeta, vault: vault)
            if let position = result.position {
                if result.isAPIBacked {
                    apiPositions.append(position)
                } else {
                    fallbackPositions.append(position)
                }
            }
        }

        let allPositions = (apiPositions + fallbackPositions).sorted { $0.amount > $1.amount }

        // Only persist API-backed positions; fallback positions are ephemeral
        if !apiPositions.isEmpty {
            let sortedAPIPositions = apiPositions.sorted { $0.amount > $1.amount }
            await savePositions(positions: sortedAPIPositions)
        }

        return allPositions
    }
}

private extension THORChainStakeInteractor {
    struct StakePositionResult {
        let position: StakePosition?
        let isAPIBacked: Bool
    }

    func createStakePosition(for coin: Coin, runeCoin: Coin?, coinMeta: CoinMeta, vault: Vault) async -> StakePositionResult {
        let ticker = coin.ticker.uppercased()
        switch ticker {
        case "TCY", "RUJI":
            // Avoid noisy logs if TCY is tracked but RUNE is missing
            if ticker == "TCY" && runeCoin == nil {
                return StakePositionResult(position: nil, isAPIBacked: false)
            }
            do {
                let details = try await stakingService.fetchStakingDetails(
                    coin: coin,
                    runeCoin: runeCoin,
                    address: coin.address
                )

                let position = StakePosition(
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
                return StakePositionResult(position: position, isAPIBacked: true)
            } catch {
                print("Error fetching \(ticker) staking details: \(error.localizedDescription)")
                // Fallback to using local staked balance — ephemeral, not persisted
                let position = StakePosition(
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
                return StakePositionResult(position: position, isAPIBacked: false)
            }

        case "YRUNE", "YTCY":
            let position = StakePosition(
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
            return StakePositionResult(position: position, isAPIBacked: true)
        default:
            // Default case for other stake positions
            let position = StakePosition(
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
            return StakePositionResult(position: position, isAPIBacked: true)
        }
    }

    @MainActor
    private func savePositions(positions: [StakePosition]) {
        do {
            try DefiPositionsStorageService().upsert(positions)
        } catch {
            print("An error occured while saving staked positions: \(error)")
        }
    }
}
