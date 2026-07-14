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

    /// Resolves the Staked RUJI amount shown on the DeFi card.
    ///
    /// Prefers the on-chain `x/staking-x/ruji` receipt balance (`onChainRaw`, unscaled) —
    /// the source of truth — over the Rujira staking API's already-scaled `bonded` amount,
    /// which can report zero even while receipts are held. `onChainRaw == nil` means the
    /// on-chain read failed, so fall back to `bonded`; a successful zero stays zero.
    static func resolveRujiStakedAmount(onChainRaw: Decimal?, bonded: Decimal, decimals: Int) -> Decimal {
        guard let onChainRaw else { return bonded }
        return scaledAmount(rawAmount: onChainRaw, decimals: decimals)
    }

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        // Snapshot every `@Model` value the async branch will need on `MainActor`, then operate
        // exclusively on value types.
        guard let runeMeta = await runeMeta(in: vault) else { return [] }
        let snapshots = await coinSnapshots(in: vault)

        var dtos: [StakePositionData] = []
        for snapshot in snapshots {
            if let dto = await dto(for: snapshot, runeMeta: runeMeta) {
                dtos.append(dto)
            }
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

    func dto(for snapshot: CoinSnapshot, runeMeta: CoinMeta) async -> StakePositionData? {
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
                return StakePositionData(
                    coin: snapshot.meta,
                    type: type,
                    amount: details.stakedAmount,
                    apr: details.apr,
                    estimatedReward: details.estimatedReward,
                    nextPayout: details.nextPayoutDate,
                    rewards: details.rewards,
                    rewardCoin: details.rewardsCoin
                )
            } catch {
                logger.error("Error fetching TCY staking details: \(error.localizedDescription, privacy: .private)")
                return nil
            }

        case "RUJI":
            do {
                let details = try await stakingService.fetchStakingDetails(
                    coinMeta: snapshot.meta,
                    runeCoinMeta: runeMeta,
                    address: snapshot.address
                )
                // The Rujira staking API's `bonded.amount` (surfaced as `details.stakedAmount`)
                // can report zero even while sRUJI receipts are held on-chain. Prefer the
                // on-chain `x/staking-x/ruji` receipt balance as the source of truth; a
                // successful read — including a genuine zero — wins. Fall back to the API
                // amount only when the on-chain read fails (throws → nil via `try?`).
                let onChainRaw = try? await ThorchainService.shared.fetchRujiStakingReceiptAmount(address: snapshot.address)
                let amount = THORChainStakeInteractor.resolveRujiStakedAmount(
                    onChainRaw: onChainRaw,
                    bonded: details.stakedAmount,
                    decimals: snapshot.meta.decimals
                )
                return StakePositionData(
                    coin: snapshot.meta,
                    type: type,
                    amount: amount,
                    apr: details.apr,
                    estimatedReward: details.estimatedReward,
                    nextPayout: details.nextPayoutDate,
                    rewards: details.rewards,
                    rewardCoin: details.rewardsCoin
                )
            } catch {
                logger.error("Error fetching RUJI staking details: \(error.localizedDescription, privacy: .private)")
                return nil
            }

        case "STCY":
            do {
                let rawAmount = try await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: snapshot.address)
                let amount = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: snapshot.meta.decimals)
                return StakePositionData(coin: snapshot.meta, type: type, amount: amount)
            } catch {
                logger.error("Error fetching STCY auto-compound amount: \(error.localizedDescription, privacy: .private)")
                return nil
            }

        case "YBRUNE":
            do {
                let rawAmount = try await ThorchainService.shared.fetchBRuneAutoCompoundAmount(address: snapshot.address)
                let amount = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: snapshot.meta.decimals)
                return StakePositionData(coin: snapshot.meta, type: type, amount: amount)
            } catch {
                logger.error("Error fetching ybRUNE auto-compound amount: \(error.localizedDescription, privacy: .private)")
                return nil
            }

        case "YRUNE", "YTCY":
            // Reads `coin.balanceDecimal` (kept up-to-date by `BalanceService`). Only update the
            // persisted row when balance is non-zero — `BalanceService` may briefly observe zero
            // mid-refresh, which would otherwise clobber a previously good amount.
            guard snapshot.balance > 0 else { return nil }
            return StakePositionData(coin: snapshot.meta, type: type, amount: snapshot.balance)

        default:
            // Same rationale as YRUNE/YTCY — `coin.stakedBalanceDecimal` mirrors a chain read
            // that can transiently report zero.
            guard snapshot.stakedBalance > 0 else { return nil }
            return StakePositionData(coin: snapshot.meta, type: type, amount: snapshot.stakedBalance)
        }
    }
}
