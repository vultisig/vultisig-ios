//
//  MayaChainAPIService+Staking.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

extension MayaChainAPIService {
    /// Fetch CACAO pool staking position for an address
    func getCacaoPoolPosition(address: String) async throws -> MayaCacaoPoolPosition {
        let response = try await httpClient.request(
            MayaChainStakingAPI.getCacaoPoolMember(address: address),
            responseType: MayaCacaoPoolMemberResponse.self
        )

        let member = response.data
        // Calculate net deposit
        let cacaoDeposit = Decimal(string: member.depositAmount) ?? 0
        let cacaoWithdrawn = Decimal(string: member.withdrawAmount) ?? 0
        let userUnits = Decimal(string: member.units) ?? 0
        let currentValue = Decimal(string: member.value) ?? 0

        let netDeposit = cacaoDeposit - cacaoWithdrawn

        return MayaCacaoPoolPosition(
            address: address,
            stakedAmount: currentValue,  // Use value for display (includes earnings)
            availableUnits: userUnits,   // Units available for unstaking
            userUnits: userUnits,
            netDeposit: netDeposit,
            lastWithdrawHeight: member.lastWithdrawHeight,
            lastDepositHeight: member.lastDepositHeight
        )
    }

    /// Get global CACAO pool state (depth and units)
    private func getCacaoPoolGlobalState() async throws -> (poolDepth: Decimal, poolUnits: Decimal) {
        // Get pool units from history endpoint
        let historyResponse = try await httpClient.request(
            MayaChainStakingAPI.getCacaoPoolHistory(interval: "day", count: 1),
            responseType: MayaCacaoPoolHistoryResponse.self
        )

        guard let latestInterval = historyResponse.data.intervals.first else {
            throw MayaChainAPIError.invalidResponse
        }

        let poolUnits = Decimal(string: latestInterval.units) ?? 0

        // Get pool depth from network endpoint (totalPooledRune = total CACAO in pool)
        let networkInfo = try await getNetwork()
        guard let totalPooledRune = networkInfo.totalPooledRune,
              let poolDepth = Decimal(string: totalPooledRune) else {
            throw MayaChainAPIError.invalidResponse
        }

        // Convert from atomic units to CACAO (10 decimals)
        let poolDepthCacao = poolDepth / pow(10, 10)
        let poolUnitsCacao = poolUnits / pow(10, 10)

        return (poolDepthCacao, poolUnitsCacao)
    }

    /// Get CACAO pool APR/APY from network endpoint
    func getCacaoPoolAPR() async throws -> (apr: Double, apy: Double) {
        // Get liquidity APY from network endpoint
        let networkInfo = try await getNetwork()

        guard let liquidityAPYString = networkInfo.liquidityAPY,
              let liquidityAPY = Double(liquidityAPYString) else {
            return (0, 0)
        }

        // liquidityAPY is already the APY value
        let apy = liquidityAPY

        // Calculate APR from APY: APR = ((1 + APY)^(1/365) - 1) * 365
        // Or simplified approximation: APR ≈ APY / (1 + APY/2)
        // For better accuracy, use the reverse formula
        let apr = (pow(1 + apy, 1.0/365.0) - 1) * 365.0

        return (apr, apy)
    }

    /// Get maximum stakeable CACAO amount (wallet balance minus gas)
    func getStakeableCacaoAmount(walletBalance: Decimal) -> Decimal {
        // Reserve gas fee (estimate ~0.1 CACAO for transaction fee)
        let estimatedGasFee: Decimal = 0.1

        // Minimum stake should be at least 1 CACAO
        let minStake: Decimal = 1.0

        let stakeable = max(0, walletBalance - estimatedGasFee)

        return stakeable >= minStake ? stakeable : 0
    }

    /// Get bondable deposit assets (async version)
    /// Returns array of CoinMeta for assets that can be bonded on MayaChain
    func getDepositAssets() async throws -> [THORChainAsset] {
        let pools = try await getPools()

        // Filter bondable pools and map to CoinMeta
        let bondableAssets = pools
            .filter { $0.bondable }
            .compactMap { pool -> THORChainAsset? in
                // Parse asset format: "CHAIN.SYMBOL" or "CHAIN.SYMBOL-ADDRESS"
                // Example: "ETH.ETH", "ETH.USDC-0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
                // Use THORChainAssetFactory which handles the same format
                guard let coin = THORChainAssetFactory.createCoin(from: pool.asset) else {
                    return nil
                }
                return THORChainAsset(thorchainAsset: pool.asset, asset: coin)
            }

        return bondableAssets
    }
}

// MARK: - Staking Models

struct MayaCacaoPoolPosition {
    let address: String
    let stakedAmount: Decimal      // Current value in CACAO (for display)
    let availableUnits: Decimal    // Units available for unstaking
    let userUnits: Decimal         // User's pool units
    let netDeposit: Decimal        // Deposit - Withdrawn
    let lastWithdrawHeight: Int64
    let lastDepositHeight: Int64
}
