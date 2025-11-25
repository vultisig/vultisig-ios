//
//  MayaChainAPIService+LPs.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/11/2025.
//

import Foundation

extension MayaChainAPIService {

    // MARK: - Liquidity Pool Methods

    /// Fetches detailed statistics for all MayaChain pools
    /// - Parameter period: Optional time period for APR calculation (e.g., "100d", "30d", "7d"). Default is 30 days.
    /// - Returns: Array of pool statistics with APR
    func getPoolStats(period: String? = nil) async throws -> [MayaPoolStats] {
        // Check cache first (only if using default period)
        if period == nil, let cached = await cache.getCachedPoolStats() {
            return cached
        }

        let response = try await httpClient.request(
            MayaChainLPsAPI.getPoolStats(period: period),
            responseType: [MayaPoolStats].self
        )
        let data = response.data

        // Cache the result (only if using default period)
        if period == nil {
            await cache.cachePoolStats(data)
        }

        return data
    }

    /// Fetches member details including all LP positions
    /// - Parameter address: The wallet address to lookup
    /// - Returns: Member details with all pool positions
    func getMemberDetails(address: String) async throws -> MayaMemberDetails {
        let response = try await httpClient.request(
            MayaChainLPsAPI.getMemberDetails(address: address),
            responseType: MayaMemberDetails.self
        )
        return response.data
    }

    /// Fetches complete LP positions for an address with calculated current values
    /// - Parameters:
    ///   - address: The MayaChain or asset address to lookup
    ///   - userLPs: The list of user-selected LP coins
    ///   - period: Optional time period for APR calculation (e.g., "30d", "100d"). Defaults to "30d".
    /// - Returns: Array of complete LP positions with current values and APR
    func getLPPositions(address: String, userLPs: [CoinMeta], period: String? = nil) async throws -> [THORChainLPPosition] {
        // Fetch pool stats and member details in parallel
        async let poolStatsTask = getPoolStats(period: period)
        async let memberDetailsTask = getMemberDetails(address: address)

        let (poolStats, memberDetails) = try await (poolStatsTask, memberDetailsTask)

        var positions: [THORChainLPPosition] = []

        // Filter pools by user selection
        let userPoolAssets = Set(userLPs.map { coin -> String in
            // Convert coin to pool asset format (e.g., "BTC.BTC", "ETH.ETH")
            let chain = coin.chain.swapAsset.uppercased()
            return "\(chain).\(coin.ticker.uppercased())"
        })

        // Process each member pool position
        for memberPool in memberDetails.pools {
            // Check if this pool is in the user's selected LPs
            guard userPoolAssets.contains(memberPool.pool) else {
                continue
            }

            // Find matching pool stats
            guard let poolStat = poolStats.first(where: { $0.asset == memberPool.pool }),
                  poolStat.isAvailable else {
                continue
            }

            // Create THORChainLPPosition (reusing the same model for MayaChain)
            let position = THORChainLPPosition(
                runeRedeemValue: memberPool.runeAdded,
                assetRedeemValue: memberPool.assetAdded,
                poolStats: THORChainPoolStats(
                    asset: poolStat.asset,
                    assetDepth: poolStat.assetDepth,
                    runeDepth: poolStat.runeDepth,
                    liquidityUnits: poolStat.liquidityUnits,
                    annualPercentageRate: poolStat.annualPercentageRate,
                    poolAPY: poolStat.poolAPY,
                    assetPrice: poolStat.assetPrice,
                    assetPriceUSD: poolStat.assetPriceUSD,
                    status: poolStat.status,
                    synthUnits: poolStat.synthUnits,
                    synthSupply: poolStat.synthSupply,
                    earningsAnnualAsPercentOfDepth: poolStat.earningsAnnualAsPercentOfDepth,
                    lpLuvi: poolStat.lpLuvi,
                    saversAPR: poolStat.saversAPR,
                    units: poolStat.units
                )
            )

            positions.append(position)
        }

        return positions
    }
}

// MARK: - Cache Extension

extension MayaChainAPICache {
    private static var poolStatsCache: (data: [MayaPoolStats], timestamp: Date)?

    func getCachedPoolStats() -> [MayaPoolStats]? {
        guard let cached = MayaChainAPICache.poolStatsCache,
              Date().timeIntervalSince(cached.timestamp) < 300 else {
            return nil
        }
        return cached.data
    }

    func cachePoolStats(_ data: [MayaPoolStats]) {
        MayaChainAPICache.poolStatsCache = (data, Date())
    }
}
