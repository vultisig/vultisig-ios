//
//  TronStakeInteractor.swift
//  VultisigApp
//
//  Persists the user's frozen + unfreezing TRX (Stake 2.0) as a single
//  `StakePosition` so the DeFi Portfolio row aggregates the staked amount
//  the same way THORChain / MayaChain do — see `DefiBalanceService`.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "tron-stake-interactor")

private struct TrxSnapshot {
    let meta: CoinMeta
    let address: String
}

struct TronStakeInteractor: StakeInteractor {
    private let tronService: TronService

    init(tronService: TronService = .shared) {
        self.tronService = tronService
    }

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        // Snapshot the value-type fields off the `@Model` Coin while on `MainActor`,
        // then call the network off-actor.
        guard let snapshot = await trxSnapshot(in: vault) else { return [] }

        let vaultStakeCoins = await vaultStakeCoins(in: vault)
        guard vaultStakeCoins.contains(where: { $0.ticker == snapshot.meta.ticker }) else {
            return []
        }

        do {
            let account = try await tronService.getAccount(address: snapshot.address)
            let frozenSun = account.frozenBandwidthSun + account.frozenEnergySun + account.unfreezingTotalSun
            let amount = Decimal(frozenSun) / Decimal(1_000_000)

            return [
                StakePositionData(
                    coin: snapshot.meta,
                    type: .stake,
                    amount: amount,
                    availableToUnstake: amount
                )
            ]
        } catch {
            // Mirror the per-coin partial-failure protection used by THORChain / MayaChain
            // — omit the position so any previously persisted record stays intact.
            logger.error("Error fetching TRON frozen balance: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }
}

private extension TronStakeInteractor {
    @MainActor
    func trxSnapshot(in vault: Vault) -> TrxSnapshot? {
        guard let coin = vault.nativeCoin(for: .tron) else { return nil }
        return TrxSnapshot(meta: coin.toCoinMeta(), address: coin.address)
    }

    @MainActor
    func vaultStakeCoins(in vault: Vault) -> [CoinMeta] {
        vault.defiPositions.first { $0.chain == .tron }?.staking ?? []
    }
}
