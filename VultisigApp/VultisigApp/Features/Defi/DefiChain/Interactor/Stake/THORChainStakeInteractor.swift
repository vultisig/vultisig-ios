//
//  THORChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-stake-interactor")

struct THORChainStakeInteractor: StakeInteractor {
    private let stakingService = THORChainStakingService.shared

    static func scaledAmount(rawAmount: Decimal, decimals: Int) -> Decimal {
        rawAmount / pow(10, decimals)
    }

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        guard let runeCoin = vault.runeCoin else { return [] }
        let vaultStakePositions = await readVaultStakePositions(vault: vault)

        var positions: [StakePositionData] = []
        for coinMeta in vaultStakePositions {
            guard let coin = await coin(for: coinMeta, vault: vault) else { continue }
            if let position = await createStakePosition(for: coin, runeCoin: runeCoin, coinMeta: coinMeta) {
                positions.append(position)
            }
            // On per-coin fetch failures we omit the position. The previously persisted
            // `StakePosition` for that coin remains untouched in `vault.stakePositions`,
            // so the user keeps seeing stale-but-non-empty data until the next refresh.
        }

        return positions.sorted { $0.amount > $1.amount }
    }
}

private extension THORChainStakeInteractor {
    @MainActor
    func readVaultStakePositions(vault: Vault) -> [CoinMeta] {
        vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []
    }

    @MainActor
    func coin(for coinMeta: CoinMeta, vault: Vault) -> Coin? {
        vault.coins.first { $0.ticker == coinMeta.ticker && $0.chain == coinMeta.chain }
    }

    @MainActor
    func balance(for coin: Coin) -> Decimal {
        coin.balanceDecimal
    }

    @MainActor
    func stakedBalance(for coin: Coin) -> Decimal {
        coin.stakedBalanceDecimal
    }

    func createStakePosition(for coin: Coin, runeCoin: Coin, coinMeta: CoinMeta) async -> StakePositionData? {
        let ticker = coin.ticker.uppercased()
        switch ticker {
        case "TCY", "RUJI":
            do {
                let details = try await stakingService.fetchStakingDetails(
                    coin: coin,
                    runeCoin: runeCoin,
                    address: coin.address
                )
                return StakePositionData(
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
                logger.error("Error fetching \(ticker, privacy: .public) staking details: \(error.localizedDescription, privacy: .public)")
                return nil
            }

        case "STCY":
            let rawAmount = await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: coin.address)
            let amount = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: coinMeta.decimals)
            return StakePositionData(
                coin: coinMeta,
                type: .compound,
                amount: amount
            )

        case "YRUNE", "YTCY":
            return StakePositionData(
                coin: coinMeta,
                type: .index,
                amount: await balance(for: coin)
            )
        default:
            return StakePositionData(
                coin: coinMeta,
                type: .stake,
                amount: await stakedBalance(for: coin)
            )
        }
    }
}
