//
//  MayaChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "mayachain-stake-interactor")

private struct CacaoSnapshot {
    let meta: CoinMeta
    let address: String
    let decimals: Int
}

struct MayaChainStakeInteractor: StakeInteractor {
    private let mayaChainAPIService = MayaChainAPIService()

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        // Snapshot the value-type fields off the `@Model` Coin while we're on `MainActor`,
        // then operate exclusively on value types in the async branch.
        guard let cacao = await cacaoSnapshot(in: vault) else { return [] }

        let vaultStakePositions = await vaultStakePositions(in: vault)
        guard vaultStakePositions.contains(where: { $0.ticker == cacao.meta.ticker }) else {
            return []
        }

        guard
            let health = try? await mayaChainAPIService.getHealth(shouldCache: false),
            let mimir = try? await mayaChainAPIService.getMimir()
        else {
            logger.error("Could not fetch health and mimir for Maya chain")
            return []
        }

        do {
            let position = try await mayaChainAPIService.getCacaoPoolPosition(address: cacao.address)

            // Use value for display amount (includes earnings)
            let stakedAmount = position.stakedAmount / pow(10, cacao.decimals)
            // Use units for unstake amount (what can actually be withdrawn)
            let availableToUnstake = position.availableUnits / pow(10, cacao.decimals)

            let aprData = try? await mayaChainAPIService.getCacaoPoolAPR()

            let unstakeMetadata = calculateUnstakeMetadata(
                currentHeight: health.lastMayaNode.height,
                lastDepositHeight: position.lastDepositHeight,
                maturityBlocks: mimir.cacaoPoolDepositMaturityBlocks
            )

            return [
                StakePositionData(
                    coin: cacao.meta,
                    type: .stake,
                    amount: stakedAmount,
                    availableToUnstake: availableToUnstake,
                    apr: aprData?.apr ?? 0,
                    unstakeMetadata: unstakeMetadata
                )
            ]
        } catch {
            // On API failure, omit the position. The previously persisted CACAO @Model
            // remains untouched in `vault.stakePositions`, so the user keeps seeing
            // stale data until the next refresh — see THORChainStakeInteractor.
            logger.error("Error fetching Maya CACAO staking details: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

private extension MayaChainStakeInteractor {
    @MainActor
    func cacaoSnapshot(in vault: Vault) -> CacaoSnapshot? {
        guard let coin = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken }) else {
            return nil
        }
        return CacaoSnapshot(meta: coin.toCoinMeta(), address: coin.address, decimals: coin.decimals)
    }

    @MainActor
    func vaultStakePositions(in vault: Vault) -> [CoinMeta] {
        vault.defiPositions.first { $0.chain == .mayaChain }?.staking ?? []
    }

    func calculateUnstakeMetadata(
        currentHeight: Int64,
        lastDepositHeight: Int64,
        maturityBlocks: Int64
    ) -> UnstakeMetadata? {
        let differenceBlocks = currentHeight - lastDepositHeight

        // If maturity has been reached, no metadata needed
        guard differenceBlocks < maturityBlocks else {
            return nil
        }

        let blocksPerDay: Double = 14400
        let blocksRemaining = maturityBlocks - differenceBlocks
        let daysRemaining = Double(blocksRemaining) / blocksPerDay
        let secondsRemaining = daysRemaining * 24 * 60 * 60
        let unstakeAvailableDate = Date().addingTimeInterval(secondsRemaining)

        return UnstakeMetadata(unstakeAvailableDate: unstakeAvailableDate.timeIntervalSince1970)
    }
}
