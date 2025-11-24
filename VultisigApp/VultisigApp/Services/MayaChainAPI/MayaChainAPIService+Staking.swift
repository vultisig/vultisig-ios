//
//  MayaChainAPIService+Staking.swift
//  VultisigApp
//
//  Created by AI Assistant on 23/11/2025.
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
        let cacaoDeposit = Decimal(string: member.cacaoDeposit) ?? 0
        let cacaoWithdrawn = Decimal(string: member.cacaoWithdrawn) ?? 0
        let userUnits = Decimal(string: member.liquidityUnits) ?? 0

        let netDeposit = cacaoDeposit - cacaoWithdrawn

        // Get current pool state to calculate current value
        let poolData = try await getCacaoPoolGlobalState()

        // Calculate user's share
        let share = poolData.poolUnits > 0 ? userUnits / poolData.poolUnits : 0
        let currentCacao = poolData.poolDepth * share

        // Calculate PnL
        let pnl = currentCacao - netDeposit

        return MayaCacaoPoolPosition(
            address: address,
            stakedAmount: currentCacao,
            userUnits: userUnits,
            netDeposit: netDeposit,
            pnl: pnl
        )
    }

    /// Get global CACAO pool state (depth and units)
    private func getCacaoPoolGlobalState() async throws -> (poolDepth: Decimal, poolUnits: Decimal) {
        // Get CACAO pool history to get current state
        let response = try await httpClient.request(
            MayaChainStakingAPI.getCacaoPoolHistory(interval: "day", count: 1),
            responseType: MayaCacaoPoolHistoryResponse.self
        )

        guard let latestInterval = response.data.intervals.first else {
            throw MayaChainAPIError.invalidResponse
        }

        let poolDepth = Decimal(string: latestInterval.cacaoDepth) ?? 0
        let poolUnits = Decimal(string: latestInterval.cacaoPoolUnits) ?? 0

        // Convert from satoshis to CACAO (10 decimals)
        let poolDepthCacao = poolDepth / pow(10, 10)
        let poolUnitsCacao = poolUnits / pow(10, 10)

        return (poolDepthCacao, poolUnitsCacao)
    }

    /// Calculate CACAO pool APR/APY from historical data
    func getCacaoPoolAPR() async throws -> (apr: Double, apy: Double) {
        let response = try await httpClient.request(
            MayaChainStakingAPI.getCacaoPoolHistory(interval: "day", count: 30),
            responseType: MayaCacaoPoolHistoryResponse.self
        )

        let intervals = response.data.intervals
        guard intervals.count >= 2 else {
            return (0, 0)
        }

        // Sort by start time (newest first)
        let sorted = intervals.sorted { $0.startTime > $1.startTime }

        // Calculate value per unit for first and last interval
        guard let newest = sorted.first,
              let oldest = sorted.last,
              let newestDepth = Decimal(string: newest.cacaoDepth),
              let newestUnits = Decimal(string: newest.cacaoPoolUnits),
              let oldestDepth = Decimal(string: oldest.cacaoDepth),
              let oldestUnits = Decimal(string: oldest.cacaoPoolUnits),
              newestUnits > 0,
              oldestUnits > 0 else {
            return (0, 0)
        }

        let v1 = newestDepth / newestUnits
        let v0 = oldestDepth / oldestUnits

        guard v0 > 0 else { return (0, 0) }

        // Calculate ROI
        let roi = (v1 / v0) - 1

        // Annualize (intervals.count days to 365 days)
        let days = Double(intervals.count)
        let apr = Double(truncating: roi as NSNumber) * (365.0 / days)

        // Calculate APY from APR: APY = (1 + APR/365)^365 - 1
        let apy = pow(1 + apr / 365, 365) - 1

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
}

// MARK: - Staking Models

struct MayaCacaoPoolPosition {
    let address: String
    let stakedAmount: Decimal     // Current value in CACAO
    let userUnits: Decimal         // User's pool units
    let netDeposit: Decimal        // Deposit - Withdrawn
    let pnl: Decimal               // Profit/Loss
}
