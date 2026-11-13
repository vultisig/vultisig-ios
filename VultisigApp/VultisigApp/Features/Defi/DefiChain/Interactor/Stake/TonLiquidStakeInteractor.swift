//
//  TonLiquidStakeInteractor.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-liquid-stake-interactor")

/// Builds the Tonstakers (tsTON) position for the DeFi tab, beside the nominator position.
///
/// Like the nominator position it is not gated behind the per-coin opt-in, so the card and its
/// Stake action are always reachable (Android parity). The position is the tsTON balance, keyed
/// by the tsTON `CoinMeta` and priced by the tsTON feed; the tsTON→TON rate is read only to say
/// what an unstake returns.
struct TonLiquidStakeInteractor: StakeInteractor {
    private let service = TonService.shared

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        guard let address = await tonAddress(in: vault) else { return [] }
        let tston = TokensStore.tston

        let balanceRaw: String
        do {
            balanceRaw = try await service.getJettonBalance(coin: tston, address: address)
        } catch {
            logger.error("Failed to read tsTON balance: \(error.localizedDescription, privacy: .private)")
            balanceRaw = .zero
        }
        let balance = (Decimal(string: balanceRaw) ?? 0) / pow(Decimal(10), tston.decimals)

        let poolInfo = await service.getStakingPoolInfo(poolAddress: Tonstakers.poolAddress)
        // tonapi reports `apy` as a percentage; the card formats a fraction.
        let apr: Double? = poolInfo?.apy.map { $0 / 100 }

        return [
            StakePositionData(
                coin: tston,
                type: .liquid,
                amount: balance,
                availableToUnstake: balance,
                apr: apr,
                poolAddress: Tonstakers.poolAddress,
                poolName: "Tonstakers"
            )
        ]
    }
}

private extension TonLiquidStakeInteractor {
    @MainActor
    func tonAddress(in vault: Vault) -> String? {
        vault.coins.first { $0.chain == .ton && $0.isNativeToken }?.address
    }
}
