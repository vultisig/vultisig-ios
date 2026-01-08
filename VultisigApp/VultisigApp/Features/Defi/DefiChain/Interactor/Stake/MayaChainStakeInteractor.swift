//
//  MayaChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

struct MayaChainStakeInteractor: StakeInteractor {
    private let mayaChainAPIService = MayaChainAPIService()

    func fetchStakePositions(vault: Vault) async -> [StakePosition] {
        // Get CACAO coin (native token for MayaChain)
        guard let cacaoCoin = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken }) else {
            return []
        }

        // Check if user has CACAO staking enabled in vault DeFi positions
        let vaultStakePositions = vault.defiPositions.first { $0.chain == .mayaChain }?.staking ?? []

        // Only fetch staking details if CACAO is in the enabled positions
        guard vaultStakePositions.contains(where: { $0.ticker == cacaoCoin.ticker }) else {
            return []
        }
        
        guard
            let health = try? await mayaChainAPIService.getHealth(shouldCache: false),
            let mimir = try? await mayaChainAPIService.getMimir()
        else {
            print("Could not fetch health and mimir for Maya chain")
            return []
        }

        do {
            // Fetch CACAO pool position
            let position = try await mayaChainAPIService.getCacaoPoolPosition(address: cacaoCoin.address)

            // Use value for display amount (includes earnings)
            let stakedAmount = position.stakedAmount / pow(10, cacaoCoin.decimals)
            // Use units for unstake amount (what can actually be withdrawn)
            let availableToUnstake = position.availableUnits / pow(10, cacaoCoin.decimals)

            // Fetch APR/APY
            let aprData = try? await mayaChainAPIService.getCacaoPoolAPR()

            // Check for withdrawal date
            let unstakeMetadata = calculateUnstakeMetadata(
                currentHeight: health.lastMayaNode.height,
                lastDepositHeight: position.lastDepositHeight,
                maturityBlocks: mimir.cacaoPoolDepositMaturityBlocks
            )

            // Create stake position
            let stakePosition = StakePosition(
                coin: cacaoCoin.toCoinMeta(),
                type: .stake,
                amount: stakedAmount,
                availableToUnstake: availableToUnstake,
                apr: aprData?.apr ?? 0,
                estimatedReward: nil,  // CACAO pool doesn't show estimated rewards separately
                nextPayout: nil,  // CACAO pool rewards are continuously accrued
                rewards: nil,
                rewardCoin: nil,  // Rewards in CACAO
                unstakeMetadata: unstakeMetadata,
                vault: vault
            )

            let positions = [stakePosition]
            await savePositions(positions: positions)
            return positions
        } catch {
            print("Error fetching Maya CACAO staking details: \(error.localizedDescription)")

            // Fallback to using local staked balance if API fails
            let fallbackPosition = StakePosition(
                coin: cacaoCoin.toCoinMeta(),
                type: .stake,
                amount: cacaoCoin.stakedBalanceDecimal,
                apr: nil,
                estimatedReward: nil,
                nextPayout: nil,
                rewards: nil,
                rewardCoin: nil,
                vault: vault
            )

            return [fallbackPosition]
        }
    }
}

private extension MayaChainStakeInteractor {
    @MainActor
    func savePositions(positions: [StakePosition]) async {
        do {
            try DefiPositionsStorageService().upsert(positions)
        } catch {
            print("An error occurred while saving staked positions: \(error)")
        }
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
