//
//  THORChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-stake-interactor")

struct THORChainStakeInteractor: StakeInteractor {
    private let stakingService: THORChainStakingProviding

    init(stakingService: THORChainStakingProviding = THORChainStakingService.shared) {
        self.stakingService = stakingService
    }

    static func scaledAmount(rawAmount: Decimal, decimals: Int) -> Decimal {
        rawAmount / pow(10, decimals)
    }

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        // Snapshot every `@Model` value the async branch will need on `MainActor`, then operate
        // exclusively on value types.
        guard let runeMeta = await runeMeta(in: vault) else { return [] }
        let snapshots = await coinSnapshots(in: vault)

        var dtos: [StakePositionData] = []
        for snapshot in snapshots {
            dtos.append(contentsOf: await positions(for: snapshot, runeMeta: runeMeta))
        }
        return dtos
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

    @MainActor
    func coinSnapshots(in vault: Vault) -> [CoinSnapshot] {
        let enabled = vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []
        return enabled.compactMap { meta in
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

    /// Positions contributed by one enabled coin. Returns an empty array when the
    /// read failed or the value is not trustworthy yet — storage upserts only what
    /// is returned, so the persisted row keeps its last good value.
    func positions(for snapshot: CoinSnapshot, runeMeta: CoinMeta) async -> [StakePositionData] {
        let ticker = snapshot.meta.ticker.uppercased()
        let type = StakePositionType.defaultType(for: snapshot.meta)

        switch ticker {
        case "TCY":
            do {
                let details = try await stakingService.fetchStakingDetails(
                    coinMeta: snapshot.meta,
                    runeCoinMeta: runeMeta,
                    address: snapshot.address
                )
                return [StakePositionData(
                    coin: snapshot.meta,
                    type: type,
                    amount: details.stakedAmount,
                    apr: details.apr,
                    estimatedReward: details.estimatedReward,
                    nextPayout: details.nextPayoutDate,
                    rewards: details.rewards,
                    rewardCoin: details.rewardsCoin
                )]
            } catch {
                logger.error("Error fetching TCY staking details: \(error.localizedDescription, privacy: .private)")
                return []
            }

        case "RUJI":
            // The BONDED position — staked with `account.bond`, unstaked with
            // `account.withdraw`, and the only one that accrues manually-claimable
            // USDC. It is independent of the auto-compounding position below (an
            // account can hold either, both or neither), so it reports the pool's
            // `bonded` amount alone and never substitutes the sRUJI receipt for it.
            // APR and pending revenue ride here because the auto-compounding side
            // reinvests its revenue instead of making it claimable.
            do {
                let details = try await stakingService.fetchStakingDetails(
                    coinMeta: snapshot.meta,
                    runeCoinMeta: runeMeta,
                    address: snapshot.address
                )
                return [StakePositionData(
                    coin: snapshot.meta,
                    type: type,
                    amount: details.stakedAmount,
                    apr: details.apr,
                    estimatedReward: details.estimatedReward,
                    nextPayout: details.nextPayoutDate,
                    rewards: details.rewards,
                    rewardCoin: details.rewardsCoin
                )]
            } catch {
                logger.error("Error fetching RUJI staking details: \(error.localizedDescription, privacy: .private)")
                return []
            }

        case "SRUJI":
            // The AUTO-COMPOUNDING position — staked with `liquid.bond`, unstaked
            // with `liquid.unbond`, and receipted by the sRUJI vault share. Its
            // amount is the pool's liquid size, i.e. the receipt valued in RUJI at
            // the current share price; the raw share count would understate the
            // position by that factor. Stat-free like sTCY: revenue compounds into
            // the amount rather than becoming claimable.
            do {
                let details = try await stakingService.fetchStakingDetails(
                    coinMeta: snapshot.meta,
                    runeCoinMeta: runeMeta,
                    address: snapshot.address
                )
                return [StakePositionData(coin: snapshot.meta, type: type, amount: details.autoCompoundAmount)]
            } catch {
                logger.error("Error fetching sRUJI staking details: \(error.localizedDescription, privacy: .private)")
                return []
            }

        case "STCY":
            do {
                let rawAmount = try await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: snapshot.address)
                let amount = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: snapshot.meta.decimals)
                return [StakePositionData(coin: snapshot.meta, type: type, amount: amount)]
            } catch {
                logger.error("Error fetching STCY auto-compound amount: \(error.localizedDescription, privacy: .private)")
                return []
            }

        case "YBRUNE":
            do {
                let rawAmount = try await ThorchainService.shared.fetchBRuneAutoCompoundAmount(address: snapshot.address)
                let amount = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: snapshot.meta.decimals)
                return [StakePositionData(coin: snapshot.meta, type: type, amount: amount)]
            } catch {
                logger.error("Error fetching ybRUNE auto-compound amount: \(error.localizedDescription, privacy: .private)")
                return []
            }

        case "YRUNE", "YTCY":
            // Reads `coin.balanceDecimal` (kept up-to-date by `BalanceService`). Only update the
            // persisted row when balance is non-zero — `BalanceService` may briefly observe zero
            // mid-refresh, which would otherwise clobber a previously good amount.
            guard snapshot.balance > 0 else { return [] }
            return [StakePositionData(coin: snapshot.meta, type: type, amount: snapshot.balance)]

        default:
            // Same rationale as YRUNE/YTCY — `coin.stakedBalanceDecimal` mirrors a chain read
            // that can transiently report zero.
            guard snapshot.stakedBalance > 0 else { return [] }
            return [StakePositionData(coin: snapshot.meta, type: type, amount: snapshot.stakedBalance)]
        }
    }
}
