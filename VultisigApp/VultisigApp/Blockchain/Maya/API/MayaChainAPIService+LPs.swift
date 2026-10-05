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

    /// The vault's record on `pool`, or nil when mayanode has none. Any other
    /// failure throws: a caller about to move funds must not read an outage as
    /// an empty record.
    func getLiquidityProvider(pool: String, address: String) async throws -> MayaLiquidityProvider? {
        do {
            let response = try await httpClient.request(
                MayaChainLPsAPI.getLiquidityProvider(pool: pool, address: address),
                responseType: MayaLiquidityProvider.self
            )
            return response.data
        } catch HTTPError.statusCode(404, _) {
            return nil
        }
    }

    /// Finds the vault's half-finished paired adds.
    ///
    /// The scan starts from the pool list, whose `pending_inbound_*` fields say
    /// which pools hold anyone's pending liquidity; only those are then read for
    /// `cacaoAddress`, the address mayanode keys every paired add by. Throws
    /// when the pool scan fails, so an outage is not read as "no deposits"; a
    /// failed read on one pool drops only that pool.
    func getPendingLPDeposits(cacaoAddress: String) async throws -> [MayaPendingLPDeposit] {
        let candidates = try await getNodePools().filter { pool in
            (Decimal(string: pool.pendingInboundCacao) ?? 0) > 0 || (Decimal(string: pool.pendingInboundAsset) ?? 0) > 0
        }
        guard !candidates.isEmpty else { return [] }

        let found = await withTaskGroup(of: (Int, MayaPendingLPDeposit, Int64?)?.self) { group in
            for (index, pool) in candidates.enumerated() {
                group.addTask {
                    guard let record = try? await getLiquidityProvider(pool: pool.asset, address: cacaoAddress),
                          let deposit = MayaPendingLPDeposit(pool: pool.asset, record: record) else { return nil }
                    return (index, deposit, record.lastAddHeight.flatMap { $0 > 0 ? $0 : nil })
                }
            }
            var results: [(Int, MayaPendingLPDeposit, Int64?)] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results.sorted { $0.0 < $1.0 }
        }
        guard !found.isEmpty else { return [] }

        async let mimir = try? getMimirValues()
        async let height = try? getLastBlock()
        // mimir overrides the node's default; an unreadable mimir leaves the
        // countdown unknown rather than guessed.
        let ageLimit = await mimir.map { values -> Int64 in
            values[Self.pendingAgeLimitKey].flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultPendingAgeLimit
        }
        let currentHeight = await height.flatMap { $0 > 0 ? $0 : nil }

        return found.map { _, deposit, lastAddHeight in
            var deposit = deposit
            deposit.blocksUntilRefund = MayaPendingLPDeposit.blocksUntilRefund(
                lastAddHeight: lastAddHeight,
                ageLimit: ageLimit,
                currentHeight: currentHeight
            )
            return deposit
        }
    }

    /// Mimir override for the blocks MayaChain holds a half-deposit.
    private static var pendingAgeLimitKey: String { "PENDINGLIQUIDITYAGELIMIT" }

    /// The node's `PendingLiquidityAgeLimit` constant, used when mimir carries
    /// no override: roughly a week at MayaChain's block time.
    private static var defaultPendingAgeLimit: Int64 { 100_800 }

    /// The node's pools with their status and pending inbound liquidity.
    func getNodePools() async throws -> [MayaChainPool] {
        try await httpClient.request(MayaChainLPsAPI.getNodePools, responseType: [MayaChainPool].self).data
    }

    /// Every mimir key as a number. Read raw because the LP rules look keys up by
    /// name (`PAUSELP<CHAIN>`) and a value that is not a number must not fail the
    /// whole read.
    func getMimirValues() async throws -> [String: Int64] {
        let response = try await httpClient.request(MayaChainBondsAPI.getMimir, responseType: [String: LossyInt64].self)
        return response.data.compactMapValues(\.value)
    }

    /// Fetches complete LP positions for an address with calculated current values
    /// - Parameters:
    ///   - address: The MayaChain or asset address to lookup
    ///   - userLPs: The list of user-selected LP coins
    ///   - period: Optional time period for APR calculation (e.g., "30d", "100d"). Defaults to "30d".
    /// - Returns: Array of complete LP positions with current values and APR
    /// - Note: Returns all user-selected pools, with redeem values set to "0" if no position exists
    func getLPPositions(address: String, userLPs: [CoinMeta], period: String? = nil) async throws -> [THORChainLPPosition] {
        // Fetch pool stats and member details in parallel
        async let poolStatsTask = getPoolStats(period: period)
        async let memberDetailsTask = try? getMemberDetails(address: address)

        let poolStats = try await poolStatsTask
        let memberDetails = await memberDetailsTask

        var positions: [THORChainLPPosition] = []

        let userPools = poolStats.filter {
            guard let poolCoin = THORChainAssetFactory.createCoin(from: $0.asset) else {
                return false
            }
            return userLPs.contains(poolCoin)
        }

        // Process each user-selected pool
        for poolStat in userPools where poolStat.isAvailable {
            // Check if user has a position in this pool
            let memberPool = memberDetails?.pools.first(where: { $0.pool == poolStat.asset })

            // Create THORChainLPPosition (reusing the same model for MayaChain)
            let position = THORChainLPPosition(
                runeRedeemValue: memberPool?.runeAdded ?? "0",
                assetRedeemValue: memberPool?.assetAdded ?? "0",
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

/// An integer that reads as nil rather than failing its container.
struct LossyInt64: Decodable {
    let value: Int64?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Int64.self)
    }
}
