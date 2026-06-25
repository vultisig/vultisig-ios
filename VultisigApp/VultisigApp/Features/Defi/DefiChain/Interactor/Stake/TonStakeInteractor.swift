//
//  TonStakeInteractor.swift
//  VultisigApp
//

import Foundation
import OSLog
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-stake-interactor")

private struct TonStakeSnapshot {
    let meta: CoinMeta
    let address: String
    let decimals: Int
}

/// Builds the user's TON nominator-pool staking positions for the DeFi tab.
/// Positions come from tonapi's nominator endpoint (`/v2/staking/nominator/
/// {address}/pools`) — the authoritative source, since the Vultisig
/// `/ton/v3/wallet` `pools` field does not populate. APY is decorated from
/// tonapi.io and degrades to "no APR" when unavailable. Standard nominator
/// pools support full withdrawal only, so the position carries no
/// partial-unstake metadata.
struct TonStakeInteractor: StakeInteractor {
    private let service = TonService.shared

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        guard let snapshot = await tonSnapshot(in: vault) else { return [] }

        let enabled = await vaultStakePositions(in: vault)
        guard enabled.contains(where: { $0.ticker == snapshot.meta.ticker }) else {
            return []
        }

        let pools: [TonAccountStakingInfo]
        do {
            pools = try await service.getNominatorPools(address: snapshot.address)
        } catch {
            logger.error("Error fetching TON nominator pools: \(error.localizedDescription, privacy: .private)")
            return []
        }

        // The persisted stake row is keyed by `coin`, and a TON wallet stakes
        // into a single nominator pool at a time, so aggregate into one
        // position. Pick the pool with the largest total stake (active +
        // pending) and keep its address for add-more / unstake.
        guard let primary = pools.max(by: { totalStake($0) < totalStake($1) }) else {
            return [StakePositionData(coin: snapshot.meta, type: .stake, amount: 0)]
        }

        // Include `pending_deposit`: a fresh nominator deposit sits there until
        // the next validation cycle (hours), so a just-placed stake must still
        // be visible rather than vanishing right after staking.
        let divisor = pow(Decimal(10), snapshot.decimals)
        let stakedAmount = totalStake(primary) / divisor

        let normalizedAddress = TONAddressConverter.toUserFriendly(
            address: primary.pool,
            bounceable: true,
            testnet: false
        ) ?? primary.pool

        let poolInfo = await service.getStakingPoolInfo(poolAddress: primary.pool)
        // tonapi reports `apy` as a percentage (13.27 → 13.27%); the staking
        // card formats with `.percent`, which expects the fraction.
        let apr: Double? = poolInfo?.apy.map { $0 / 100 }

        return [
            StakePositionData(
                coin: snapshot.meta,
                type: .stake,
                amount: stakedAmount,
                apr: apr,
                poolAddress: normalizedAddress,
                poolImplementation: poolInfo?.implementation
            )
        ]
    }

    /// Active stake plus the just-placed deposit awaiting the next validation
    /// cycle, in nanotons.
    private func totalStake(_ info: TonAccountStakingInfo) -> Decimal {
        Decimal(info.amount) + Decimal(info.pendingDeposit)
    }
}

private extension TonStakeInteractor {
    @MainActor
    func tonSnapshot(in vault: Vault) -> TonStakeSnapshot? {
        guard let coin = vault.coins.first(where: { $0.chain == .ton && $0.isNativeToken }) else {
            return nil
        }
        return TonStakeSnapshot(meta: coin.toCoinMeta(), address: coin.address, decimals: coin.decimals)
    }

    @MainActor
    func vaultStakePositions(in vault: Vault) -> [CoinMeta] {
        vault.defiPositions.first { $0.chain == .ton }?.staking ?? []
    }
}
