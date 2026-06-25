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
/// Positions come from the Vultisig proxy `/ton/v3/wallet` endpoint (staked
/// amount + pool contract address); APY is decorated from tonapi.io and
/// degrades to "no APR" when unavailable. Standard nominator pools support full
/// withdrawal only, so the position carries no partial-unstake metadata.
struct TonStakeInteractor: StakeInteractor {
    private let service = TonService.shared

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        guard let snapshot = await tonSnapshot(in: vault) else { return [] }

        let enabled = await vaultStakePositions(in: vault)
        guard enabled.contains(where: { $0.ticker == snapshot.meta.ticker }) else {
            return []
        }

        let pools: [TonWalletPool]
        do {
            pools = try await service.getStakedPools(address: snapshot.address)
        } catch {
            logger.error("Error fetching TON staking pools: \(error.localizedDescription, privacy: .private)")
            return []
        }

        // The persisted stake row is keyed by `coin`, and a TON wallet stakes
        // into a single nominator pool at a time, so aggregate into one
        // position. Picking the largest stake keeps the primary pool's address
        // (used for add-more / unstake) when more than one is ever returned.
        let divisor = pow(Decimal(10), snapshot.decimals)
        guard let primary = pools.max(by: {
            (Decimal(string: $0.amount) ?? 0) < (Decimal(string: $1.amount) ?? 0)
        }) else {
            return [StakePositionData(coin: snapshot.meta, type: .stake, amount: 0)]
        }

        let stakedAmount = (Decimal(string: primary.amount) ?? 0) / divisor
        let normalizedAddress = TONAddressConverter.toUserFriendly(
            address: primary.address,
            bounceable: true,
            testnet: false
        ) ?? primary.address

        let poolInfo = await service.getStakingPoolInfo(poolAddress: primary.address)
        // tonapi reports `apy` as a percentage (13.27 → 13.27%); the staking
        // card formats with `.percent`, which expects the fraction.
        let apr: Double? = poolInfo?.apy.map { $0 / 100 }

        return [
            StakePositionData(
                coin: snapshot.meta,
                type: .stake,
                amount: stakedAmount,
                apr: apr,
                poolAddress: normalizedAddress
            )
        ]
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
