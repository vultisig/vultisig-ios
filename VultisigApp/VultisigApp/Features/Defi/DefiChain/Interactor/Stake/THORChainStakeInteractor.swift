//
//  THORChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-stake-interactor")

struct THORChainStakeInteractor: StakeInteractor {
    private let thorchainAPIService = THORChainAPIService()
    private let stakingService = THORChainStakingService.shared

    static func scaledAmount(rawAmount: Decimal, decimals: Int) -> Decimal {
        rawAmount / pow(10, decimals)
    }

    func fetchStakePositions(vault: Vault) async -> [StakePosition] {
        guard let runeCoin = vault.runeCoin else { return [] }
        let vaultStakePositions = vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []

        var positions: [StakePosition] = []
        for coinMeta in vaultStakePositions {
            guard let coin = vault.coins.first(where: { $0.ticker == coinMeta.ticker && $0.chain == coinMeta.chain }) else {
                continue
            }

            if let position = await createStakePosition(for: coin, runeCoin: runeCoin, coinMeta: coinMeta, vault: vault) {
                positions.append(position)
            }
        }

        let stakePositions = positions.sorted { $0.amount > $1.amount }
        await savePositions(positions: stakePositions)
        return stakePositions
    }
}

private extension THORChainStakeInteractor {
    func createStakePosition(for coin: Coin, runeCoin: Coin, coinMeta: CoinMeta, vault: Vault) async -> StakePosition? {
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
                logger.error("Error fetching \(ticker) staking details: \(error.localizedDescription)")
                // Reuse previously persisted metadata so APR / rewards / nextPayout don't disappear on transient failures
                let previous = await previousPosition(for: coin, vault: vault)
                return StakePosition(
                    coin: coinMeta,
                    type: .stake,
                    amount: coin.stakedBalanceDecimal,
                    apr: previous?.apr,
                    estimatedReward: previous?.estimatedReward,
                    nextPayout: previous?.nextPayout,
                    rewards: previous?.rewards,
                    rewardCoin: previous?.rewardCoin,
                    vault: vault
                )
            }

        case "STCY":
            let rawAmount = await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: coin.address)
            let amount = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: coinMeta.decimals)
            return StakePosition(
                coin: coinMeta,
                type: .compound,
                amount: amount,
                apr: nil,
                estimatedReward: nil,
                nextPayout: nil,
                rewards: nil,
                rewardCoin: nil,
                vault: vault
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
    private func previousPosition(for coin: Coin, vault: Vault) -> PreviousStakeMetadata? {
        let id = "\(coin.chain.ticker)_\(coin.contractAddress)_\(vault.pubKeyECDSA)"
        guard let existing = vault.stakePositions.first(where: { $0.id == id }) else {
            return nil
        }
        return PreviousStakeMetadata(
            apr: existing.apr,
            estimatedReward: existing.estimatedReward,
            nextPayout: existing.nextPayout,
            rewards: existing.rewards,
            rewardCoin: existing.rewardCoin
        )
    }

    @MainActor
    private func savePositions(positions: [StakePosition]) {
        do {
            try DefiPositionsStorageService().upsert(positions)
        } catch {
            logger.error("An error occured while saving staked positions: \(error.localizedDescription)")
        }
    }
}
