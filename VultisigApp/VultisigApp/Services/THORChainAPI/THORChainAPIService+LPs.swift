//
//  THORChainAPIService+LPs.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

extension THORChainAPIService {

    // MARK: - Liquidity Pool Methods

    /// # THORChain Pool APR Implementation
    ///
    /// This service fetches up-to-date APRs for THORChain liquidity pools using Midgard v2 API.
    ///
    /// ## Data Sources:
    /// - **Primary**: `https://midgard.ninerealms.com/v2` (public Midgard)
    /// - **Pool Stats**: `/v2/pools?status=available&period={period}`
    /// - **Depth History**: `/v2/history/depths/{asset}?interval=day&count={N}`
    ///
    /// ## LUVI-Based APR Calculation:
    ///
    /// The APR values returned by Midgard are based on LUVI (Liquidity Unit Value Index) growth.
    ///
    /// ### How LUVI APR Works:
    /// 1. **LUVI** represents the value of a single liquidity unit in the pool
    /// 2. As the pool earns fees, the LUVI increases over time
    /// 3. APR is calculated by annualizing the LUVI growth over the specified period
    ///
    /// ### Formula:
    /// ```
    /// LUVI_growth = (LUVI_end / LUVI_start) - 1
    /// APR = LUVI_growth * (365 / period_days)
    /// ```
    ///
    /// ### Example (30-day period):
    /// - LUVI at start: 1.0000
    /// - LUVI at end: 1.0200  (2% growth)
    /// - APR = 0.02 * (365 / 30) = 0.2433 = 24.33%
    ///
    /// ## Period Selection:
    /// - **1h**: Very recent performance, highest volatility
    /// - **24h**: Daily performance
    /// - **7d**: Weekly performance, higher volatility
    /// - **14d**: Two-week average
    /// - **30d**: Monthly average, balanced view (DEFAULT, matches thorchain.org)
    /// - **90d**: Quarterly average
    /// - **100d**: Longer-term average, more stable
    /// - **180d**: Semi-annual average
    /// - **365d**: Annual average
    /// - **all**: All-time average
    ///
    /// ## API Fields:
    /// - `annualPercentageRate`: Midgard's calculated APR (LUVI-based, string decimal)
    /// - `poolAPY`: APY accounting for compounding (string decimal)
    /// - `lpLuvi`: Current LUVI level for the period (string, may be "NaN")
    /// - `saversAPR`: Savers APR if applicable (string decimal)
    /// - `earningsAnnualAsPercentOfDepth`: Alternative earnings-based APR (optional)
    ///
    /// ## Manual APR Calculation:
    /// For transparency and verification, you can manually calculate APR from LUVI history:
    /// - Use `getDepthHistory(asset:interval:count:)` to fetch historical LUVI data
    /// - Use `calculateManualAPR(asset:days:)` to compute APR from the history
    /// - The manual calculation uses `meta.luviIncrease` if available, or calculates
    ///   growth from first/last interval LUVI values
    ///
    /// ## Notes:
    /// - Default period is **30d** for consistency with thorchain.org
    /// - All APR/APY values are returned as strings (e.g., "0.2433" = 24.33%)
    /// - APR does not account for compounding (use APY for that)
    /// - Past performance does not guarantee future returns
    /// - LUVI measures liquidity unit value independent of asset price changes

    /// Fetches detailed statistics for all pools
    /// - Parameter period: Optional time period for LUVI-based APR calculation (e.g., "100d", "30d", "7d"). Default is 30 days.
    ///   The period parameter affects how the APR is annualized from LUVI growth:
    ///   - "7d": APR based on 7-day LUVI growth, annualized to 365 days
    ///   - "30d": APR based on 30-day LUVI growth, annualized to 365 days (default)
    ///   - "100d": APR based on 100-day LUVI growth, annualized to 365 days
    /// - Returns: Array of pool statistics with LUVI-based APR
    func getPoolStats(period: String? = nil) async throws -> [THORChainPoolStats] {
        // Check cache first (only if using default period)
        if period == nil, let cached = await cache.getCachedPoolStats() {
            return cached
        }

        let response = try await httpClient.request(
            THORChainLPsAPI.getPoolStats(period: period),
             responseType: [THORChainPoolStats].self
        )
        let data = response.data

        // Cache the result (only if using default period)
        if period == nil {
            await cache.cachePoolStats(data)
        }

        return data
    }

    /// Fetches depth history for a pool to calculate manual APR from LUVI
    /// - Parameters:
    ///   - asset: The pool asset identifier (e.g., "BTC.BTC")
    ///   - interval: Time interval for data points (e.g., "day", "hour")
    ///   - count: Number of intervals to fetch
    /// - Returns: Depth history with LUVI data
    /// - Note: Results are cached for 5 minutes to improve performance
    func getDepthHistory(asset: String, interval: String = "day", count: Int = 30) async throws -> THORChainDepthHistory {
        // Check cache first
        if let cached = await cache.getCachedDepthHistory(asset: asset, interval: interval, count: count) {
            return cached
        }

        let response = try await httpClient.request(
            THORChainLPsAPI.getDepthHistory(asset: asset, interval: interval, count: count),
            responseType: THORChainDepthHistory.self
        )
        let data = response.data

        // Cache the result
        await cache.cacheDepthHistory(data, asset: asset, interval: interval, count: count)

        return data
    }

    /// Fetches liquidity provider details for a specific pool and address
    /// - Parameters:
    ///   - assetId: The pool asset identifier (e.g., "BTC.BTC")
    ///   - address: The wallet address to lookup
    /// - Returns: Liquidity provider response with position details
    func getLiquidityProviderDetails(assetId: String, address: String) async throws -> THORChainLiquidityProviderResponse {
        let response = try await httpClient.request(
            THORChainLPsAPI.getLiquidityProviderDetails(assetId: assetId, address: address),
            responseType: THORChainLiquidityProviderResponse.self
        )
        return response.data
    }

    /// Fetches complete LP positions for an address with calculated current values and manual APR
    /// - Parameters:
    ///   - address: The THORChain or asset address to lookup
    ///   - period: Optional time period for APR calculation (e.g., "30d", "100d"). Defaults to "30d".
    /// - Returns: Array of complete LP positions with current values and manually calculated APR from LUVI history
    /// - Note: API calls are made sequentially to respect rate limiting
    func getLPPositions(address: String, userLPs: [CoinMeta], period: String? = nil) async throws -> [THORChainLPPosition] {
        // First, fetch all pool stats to get the list of available pools
        let poolStats = try await getPoolStats(period: period)

        var positions: [THORChainLPPosition] = []

        // Filter pools by user selection
        let userPools = poolStats.filter {
            guard let poolCoin = THORChainAssetFactory.createCoin(from: $0.asset) else {
                return false
            }
            return userLPs.contains(poolCoin)
        }

        // Process each pool sequentially to respect API rate limiting
        for poolStat in userPools where poolStat.isAvailable {
            do {
                // Fetch LP details for this specific pool
                let lpDetails = try? await getLiquidityProviderDetails(
                    assetId: poolStat.asset,
                    address: address
                )

                let position = THORChainLPPosition(
                    runeRedeemValue: lpDetails?.runeDepositValue ?? "0",
                    assetRedeemValue: lpDetails?.assetDepositValue ?? "0",
                    poolStats: poolStat
                )

                positions.append(position)
            }
        }

        return positions
    }

    /// Converts period string to number of days
    /// - Parameter period: Period string (e.g., "30d", "100d", "7d")
    /// - Returns: Number of days as Int
    private func periodToDays(_ period: String?) -> Int {
        guard let period = period else { return 30 }

        // Extract number from period string (e.g., "30d" -> 30)
        let numericString = period.filter { $0.isNumber }
        if let days = Int(numericString), days > 0 {
            return days
        }

        // Handle special cases
        switch period.lowercased() {
        case "1h": return 1
        case "24h": return 1
        case "all": return 365 // Use 1 year as approximation for "all"
        default: return 30 // Default to 30 days
        }
    }

    /// Convenience method to get a single pool's LP position for an address with manual APR
    /// - Parameters:
    ///   - address: The THORChain or asset address to lookup
    ///   - poolAsset: The pool asset identifier (e.g., "BTC.BTC")
    ///   - period: Optional time period for APR calculation (e.g., "30d", "100d")
    /// - Returns: LP position for the specified pool with manually calculated APR, or nil if not found
    func getLPPosition(address: String, poolAsset: String, period: String? = nil) async throws -> THORChainLPPosition? {
        do {
            // Fetch pool stats, LP details, and manual APR in parallel
            async let poolStatsArray = getPoolStats(period: period)
            async let lpDetails = getLiquidityProviderDetails(assetId: poolAsset, address: address)

            let (stats, details) = try await (poolStatsArray, lpDetails)

            // Find the matching pool stats
            guard let poolStat = stats.first(where: { $0.asset == poolAsset }) else {
                return nil
            }

            return THORChainLPPosition(
                runeRedeemValue: details.runeRedeemValue,
                assetRedeemValue: details.assetRedeemValue,
                poolStats: poolStat
            )
        } catch {
            // User doesn't have a position in this pool
            return nil
        }
    }
}
