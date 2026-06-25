//
//  TonLiquidStakeInteractor.swift
//  VultisigApp
//

import Foundation
import OSLog
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-liquid-stake-interactor")

/// Builds the user's Tonstakers (TON liquid staking) position for the DeFi tab.
///
/// The position is valued as the user's tsTON jetton balance × the tsTON→TON
/// rate (`pool.total_amount ÷ tsTON total_supply`). It is keyed by the tsTON
/// `CoinMeta` (not native TON) so it coexists with the nominator-pool position
/// without colliding in storage. The `poolAddress` carries the Tonstakers pool
/// so the position can drive add-more / unstake actions.
struct TonLiquidStakeInteractor: StakeInteractor {
    private let service = TonService.shared

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        guard let snapshot = await tonSnapshot(in: vault) else { return [] }

        let enabled = await vaultStakePositions(in: vault)
        let tston = TokensStore.tston
        guard enabled.contains(tston) else { return [] }

        // tsTON balance is read against the tsTON master, the same jetton-balance
        // path used for any TON token. Failure degrades to a zero position so the
        // row (with its CTAs) still renders.
        let balanceRaw: String
        do {
            balanceRaw = try await service.getJettonBalance(coin: tston, address: snapshot.address)
        } catch {
            logger.error("Failed to read tsTON balance: \(error.localizedDescription, privacy: .private)")
            balanceRaw = .zero
        }

        let divisor = pow(Decimal(10), tston.decimals)
        let tsTONBalance = (Decimal(string: balanceRaw) ?? 0) / divisor

        let rate = await service.getTonstakersRate()
        // Value the position in TON terms (so its fiat reads against TON price);
        // the position coin is tsTON but the staked-equivalent is balance × rate.
        let tonValue = tsTONBalance * rate

        let poolInfo = await service.getStakingPoolInfo(poolAddress: TonstakersConstants.poolAddress)
        // tonapi reports `apy` as a percentage (14.24 → 14.24%); the staking
        // card formats with `.percent`, which expects the fraction.
        let apr: Double? = poolInfo?.apy.map { $0 / 100 }

        let normalizedPool = TONAddressConverter.toUserFriendly(
            address: TonstakersConstants.poolAddress,
            bounceable: true,
            testnet: false
        ) ?? TonstakersConstants.poolAddress

        return [
            StakePositionData(
                coin: tston,
                type: .liquid,
                amount: tonValue,
                apr: apr,
                poolAddress: normalizedPool
            )
        ]
    }
}

private extension TonLiquidStakeInteractor {
    @MainActor
    func tonSnapshot(in vault: Vault) -> (address: String, decimals: Int)? {
        guard let coin = vault.coins.first(where: { $0.chain == .ton && $0.isNativeToken }) else {
            return nil
        }
        return (coin.address, coin.decimals)
    }

    @MainActor
    func vaultStakePositions(in vault: Vault) -> [CoinMeta] {
        vault.defiPositions.first { $0.chain == .ton }?.staking ?? []
    }
}
