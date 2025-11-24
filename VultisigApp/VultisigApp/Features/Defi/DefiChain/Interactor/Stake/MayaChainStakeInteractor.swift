//
//  MayaChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

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

        do {
            // Fetch CACAO pool position
            let position = try await mayaChainAPIService.getCacaoPoolPosition(address: cacaoCoin.address)

            // Only create a position if user has staked amount
            guard position.stakedAmount > 0 else {
                return []
            }

            // Fetch APR/APY
            let aprData = try await mayaChainAPIService.getCacaoPoolAPR()

            // Create stake position
            let stakePosition = StakePosition(
                coin: cacaoCoin.toCoinMeta(),
                type: .stake,  // CACAO pool is simple staking
                amount: position.stakedAmount,
                apr: aprData.apr,
                estimatedReward: nil,  // CACAO pool doesn't show estimated rewards separately
                nextPayout: nil,  // CACAO pool rewards are continuously accrued
                rewards: position.pnl > 0 ? position.pnl : nil,  // Show positive PnL as rewards
                rewardCoin: cacaoCoin.toCoinMeta(),  // Rewards in CACAO
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
}
