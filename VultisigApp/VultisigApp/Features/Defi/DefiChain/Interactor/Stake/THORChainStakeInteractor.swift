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
        // Snapshot every `@Model` value the async branch will need on `MainActor`, then operate
        // exclusively on value types. Reading `Coin` properties off the main actor would violate
        // the SwiftData rule (`/.claude/rules/swiftdata.md`) and break under Swift 6 strict
        // concurrency.
        guard
            let runeMeta = await runeMeta(in: vault),
            let stakeSnapshots = await coinSnapshots(in: vault)
        else { return [] }

        var positions: [StakePositionData] = []
        for snapshot in stakeSnapshots {
            if let position = await createStakePosition(snapshot: snapshot, runeMeta: runeMeta) {
                positions.append(position)
            }
            // On per-coin fetch failures we omit the position. The previously persisted
            // `StakePosition` for that coin remains untouched in `vault.stakePositions`,
            // so the user keeps seeing stale-but-non-empty data until the next refresh.
        }

        return positions.sorted { $0.amount > $1.amount }
    }
}

private struct CoinSnapshot {
    let meta: CoinMeta
    let address: String
    let balance: Decimal
    let stakedBalance: Decimal
}

private extension THORChainStakeInteractor {
    @MainActor
    func runeMeta(in vault: Vault) -> CoinMeta? {
        vault.runeCoin?.toCoinMeta()
    }

    /// Reads the user's enabled stake coins (`vault.defiPositions[.thorChain].staking`),
    /// resolves each to the matching `vault.coins` row, and snapshots the value-type fields
    /// into `CoinSnapshot`. Returns `nil` if the vault has no THORChain defiPositions entry.
    @MainActor
    func coinSnapshots(in vault: Vault) -> [CoinSnapshot]? {
        let enabled = vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []
        return enabled.compactMap { meta -> CoinSnapshot? in
            guard let coin = vault.coins.first(where: { $0.ticker == meta.ticker && $0.chain == meta.chain }) else {
                return nil
            }
            return CoinSnapshot(
                meta: meta,
                address: coin.address,
                balance: coin.balanceDecimal,
                stakedBalance: coin.stakedBalanceDecimal
            )
        }
    }

    func createStakePosition(snapshot: CoinSnapshot, runeMeta: CoinMeta) async -> StakePositionData? {
        let ticker = snapshot.meta.ticker.uppercased()
        switch ticker {
        case "TCY", "RUJI":
            do {
                let details = try await stakingService.fetchStakingDetails(
                    coinMeta: snapshot.meta,
                    runeCoinMeta: runeMeta,
                    address: snapshot.address
                )
                return StakePositionData(
                    coin: snapshot.meta,
                    type: .stake,
                    amount: details.stakedAmount,
                    apr: details.apr,
                    estimatedReward: details.estimatedReward,
                    nextPayout: details.nextPayoutDate,
                    rewards: details.rewards,
                    rewardCoin: details.rewardsCoin
                )
            } catch {
                logger.error("Error fetching \(ticker, privacy: .public) staking details: \(error.localizedDescription, privacy: .private)")
                return nil
            }

        case "STCY":
            let rawAmount = await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: snapshot.address)
            let amount = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: snapshot.meta.decimals)
            return StakePositionData(
                coin: snapshot.meta,
                type: .compound,
                amount: amount
            )

        case "YRUNE", "YTCY":
            return StakePositionData(
                coin: snapshot.meta,
                type: .index,
                amount: snapshot.balance
            )

        default:
            return StakePositionData(
                coin: snapshot.meta,
                type: .stake,
                amount: snapshot.stakedBalance
            )
        }
    }
}
