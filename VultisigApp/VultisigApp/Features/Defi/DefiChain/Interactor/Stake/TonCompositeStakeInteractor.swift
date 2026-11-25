//
//  TonCompositeStakeInteractor.swift
//  VultisigApp
//

import Foundation

/// Aggregates the two coexisting TON staking position types for the DeFi tab:
/// the nominator-pool position (native TON) and the Tonstakers liquid-staking
/// position (tsTON). Each sub-interactor is keyed by a distinct `CoinMeta`, so
/// the storage upsert keeps both rows without collision.
struct TonCompositeStakeInteractor: StakeInteractor {
    private let nominator = TonStakeInteractor()
    private let liquid = TonLiquidStakeInteractor()

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        async let nominatorPositions = nominator.fetchStakePositions(vault: vault)
        async let liquidPositions = liquid.fetchStakePositions(vault: vault)
        return await nominatorPositions + liquidPositions
    }
}
