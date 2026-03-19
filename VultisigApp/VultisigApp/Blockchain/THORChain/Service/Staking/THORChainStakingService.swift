//
//  THORChainStakingService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/10/2025.
//

import Foundation
import BigInt
import OSLog

/// Service for fetching staking details for THORChain ecosystem coins (RUJI and TCY)
class THORChainStakingService {
    static let shared = THORChainStakingService()

    private let httpClient: HTTPClient
    private let logger = Logger(subsystem: "com.vultisig.wallet", category: "thorchain-staking")

    // Cache for TCY constants (they don't change often)
    private var cachedTcyConstants: TcyConstants?
    private var constantsCacheTimestamp: Date?
    private let constantsCacheDuration: TimeInterval = 3600 // 1 hour
    private let thorchainAPIService = THORChainAPIService()

    private init() {
        self.httpClient = HTTPClient()
    }

    // MARK: - TCY Constants

    struct TcyConstants {
        let minRuneForDistribution: Decimal
        let minTcyForDistribution: Decimal
        let systemIncomeBps: Int
    }

    // MARK: - Main Entry Point

    /// Fetch staking details for a given coin and address
    /// - Parameters:
    ///   - coin: The coin being staked
    ///   - runeCoin: The RUNE coin (for price lookups)
    ///   - address: The THORChain address
    /// - Returns: StakingDetails with amount, APR, rewards, etc.
    func fetchStakingDetails(coin: Coin, runeCoin: Coin, address: String) async throws -> StakingDetails {
        switch coin.ticker.uppercased() {
        case "RUJI":
            return try await fetchRujiStakingDetails(address: address)
        case "TCY":
            return try await fetchTcyStakingDetails(coin: coin, runeCoin: runeCoin, address: address)
        default:
            throw StakingError.unsupportedCoin
        }
    }

}

// MARK: - RUJI Implementation

private extension THORChainStakingService {
    /// Fetch RUJI staking details from GraphQL API
    func fetchRujiStakingDetails(address: String) async throws -> StakingDetails {
        // 1. Make GraphQL request using HTTPClient
        let target = THORChainStakingAPI.getRujiStaking(address: address)
        let response = try await httpClient.request(target, responseType: AccountRootData.self)
        let decoded = response.data

        guard let stake = decoded.data.node?.stakingV2?.first else {
            return .empty
        }

        // 2. Parse staked amount
        let stakedAmount = BigInt(stake.bonded.amount) ?? .zero
        let stakedDecimal = Decimal(string: stakedAmount.description) ?? 0
        let stakedFinal = stakedDecimal / pow(10, 8)  // RUJI has 8 decimals

        // 3. Parse rewards
        let rewardsAmount = BigInt(stake.pendingRevenue?.amount ?? "0") ?? .zero
        let rewardsDecimal = Decimal(string: rewardsAmount.description) ?? 0
        let rewardsFinal = rewardsDecimal / pow(10, 6)  // USDC has 6 decimals

        // 4. Parse APR
        let aprString = stake.pool?.summary?.apr?.value ?? "0"
        let apr = Double(aprString)

        // 5. Create USDC coin meta for rewards
        let usdcCoin = CoinMeta(
            chain: .thorChain,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: stake.pendingRevenue?.asset.metadata?.symbol ?? "USDC",
            isNativeToken: false
        )

        return StakingDetails(
            stakedAmount: stakedFinal,
            apr: apr,
            estimatedReward: nil,  // Not available for RUJI
            nextPayoutDate: nil,   // Not available for RUJI
            rewards: rewardsFinal,
            rewardsCoin: usdcCoin
        )
    }
}

// MARK: - TCY Implementation

private extension THORChainStakingService {
    /// Fetch TCY staking details
    func fetchTcyStakingDetails(coin: Coin, runeCoin: Coin, address: String) async throws -> StakingDetails {
        // 1. Fetch staked amount
        let stakedResponse = try await fetchTcyStakedAmount(address: address)
        let stakedAmount = Decimal(string: stakedResponse.amount) ?? 0
        let stakedDecimal = stakedAmount / Decimal(sign: .plus, exponent: 8, significand: 1)  // Divide by 10^8 using Decimal
        logger.info("TCY Staking - Raw: \(stakedResponse.amount), Decimal: \(String(describing: stakedAmount)), Final: \(String(describing: stakedDecimal))")

        // 2. Calculate APY and convert to APR
        let apy = try await calculateTcyAPY(tcyCoin: coin, runeCoin: runeCoin, address: address, stakedAmount: stakedDecimal)
        let apr = convertAPYtoAPR(apy)

        // 3. Calculate next payout
        let nextPayout = try await calculateTcyNextPayout()

        // 4. Calculate estimated reward
        let estimatedReward = try await calculateTcyEstimatedReward(stakedAmount: stakedDecimal)

        return StakingDetails(
            stakedAmount: stakedDecimal,
            apr: apr,
            estimatedReward: estimatedReward,
            nextPayoutDate: nextPayout,
            rewards: nil,  // TCY auto-distributes, no pending rewards
            rewardsCoin: TokensStore.rune
        )
    }

    func fetchTcyStakedAmount(address: String) async throws -> TcyStakerResponse {
        let target = THORChainStakingAPI.getTcyStakedAmount(address: address)
        let response = try await httpClient.request(target, responseType: TcyStakerResponse.self)
        return response.data
    }

    func fetchTcyDistributions(limit: Int) async throws -> [TcyDistribution] {
        let target = THORChainStakingAPI.getTcyDistributions(limit: limit)
        let response = try await httpClient.request(target, responseType: [TcyDistribution].self)
        return response.data
    }

    func fetchTcyUserDistributions(address: String) async throws -> TcyUserDistributionsResponse {
        let target = THORChainStakingAPI.getTcyUserDistributions(address: address)
        let response = try await httpClient.request(target, responseType: TcyUserDistributionsResponse.self)
        return response.data
    }

    func fetchTcyModuleBalance() async throws -> TcyModuleBalanceResponse {
        let target = THORChainStakingAPI.getTcyModuleBalance
        let response = try await httpClient.request(target, responseType: TcyModuleBalanceResponse.self)
        return response.data
    }

    func fetchThorchainConstants() async throws -> TcyConstants {
        // Check cache first
        if let cached = cachedTcyConstants,
           let timestamp = constantsCacheTimestamp,
           Date().timeIntervalSince(timestamp) < constantsCacheDuration {
            return cached
        }

        // Fetch from API using THORChainAPIService
        let data = try await thorchainAPIService.getConstants()

        // Parse constants (values are in satoshis, convert to decimal)
        let minRune = Decimal(data.int_64_values.MinRuneForTCYStakeDistribution)
        let minRuneDecimal = minRune / pow(10, 8)

        let minTcy = Decimal(data.int_64_values.MinTCYForTCYStakeDistribution ?? 0)
        let minTcyDecimal = minTcy / pow(10, 8)

        let bps = Int(data.int_64_values.TCYStakeSystemIncomeBps ?? 0)

        let constants = TcyConstants(
            minRuneForDistribution: minRuneDecimal,
            minTcyForDistribution: minTcyDecimal,
            systemIncomeBps: bps
        )

        // Cache the result
        cachedTcyConstants = constants
        constantsCacheTimestamp = Date()

        return constants
    }

    /// Convert APY to APR
    /// APY is in percentage format (e.g., 15.5 for 15.5%)
    /// Formula: APY = (1 + daily_rate)^365 - 1, APR = daily_rate * 365
    func convertAPYtoAPR(_ apy: Double) -> Double {
        guard apy > 0 else { return 0 }

        // Convert percentage to decimal (15.5% -> 0.155)
        let apyDecimal = apy / 100.0

        // Calculate daily rate from APY
        let dailyRate = pow(1 + apyDecimal, 1.0/365.0) - 1

        let apr = dailyRate * 365

        return apr
    }

    /// Calculate next TCY payout time
    /// Distributions happen every 14,400 blocks (~24 hours at 6 seconds per block)
    func calculateTcyNextPayout() async throws -> TimeInterval {
        // 1. Get current block height
        let currentBlock = try await thorchainAPIService.getLastBlock()

        // 2. Distributions happen every 14,400 blocks
        let blocksPerDay: Int64 = 14_400
        let nextDistributionBlock = ((Int64(currentBlock) / blocksPerDay) + 1) * blocksPerDay

        // 3. Calculate blocks remaining
        let blocksRemaining = nextDistributionBlock - Int64(currentBlock)

        // 4. 6 seconds per block
        let secondsRemaining = Double(blocksRemaining) * 6.0

        // 5. Return timestamp
        return Date().timeIntervalSince1970 + secondsRemaining
    }

    /// Calculate estimated TCY reward based on current module balance and accrual rate
    /// Logic mirrors: https://github.com/familiarcow/RUNE-Tools TCY.svelte calculateNextDistribution
    func calculateTcyEstimatedReward(stakedAmount: Decimal) async throws -> Decimal {
        // 1. Get current block height
        let currentBlock = try await thorchainAPIService.getLastBlock()
        logger.info("TCY Reward - Current block: \(currentBlock)")

        // 2. Calculate next distribution block (every 14,400 blocks)
        // Using Math.ceil logic: nextBlock = 14400 * Math.ceil(currentBlock / 14400)
        let blocksPerDay: UInt64 = 14_400
        let currentBlockDouble = Double(currentBlock)
        let blocksPerDayDouble = Double(blocksPerDay)
        let nextBlock = UInt64(ceil(currentBlockDouble / blocksPerDayDouble) * blocksPerDayDouble)
        let blocksRemaining = nextBlock - currentBlock
        logger.info("TCY Reward - Next block: \(nextBlock), Blocks remaining: \(blocksRemaining)")

        // 3. Get current accrued RUNE in tcy_stake module
        let moduleBalance = try await fetchTcyModuleBalance()
        guard let runeCoin = moduleBalance.coins.first(where: { $0.denom == "rune" }) else {
            logger.warning("TCY Reward - No RUNE found in module balance")
            return 0
        }

        let runeAmount = Decimal(string: runeCoin.amount) ?? 0
        let currentAccruedRune = runeAmount / pow(10, 8)
        logger.info("TCY Reward - Current accrued RUNE: \(String(describing: currentAccruedRune))")

        // 4. Calculate blocks since last distribution
        // Using Math.floor logic: lastDistributionBlock = 14400 * Math.floor(currentBlock / 14400)
        let lastDistributionBlock = (currentBlock / blocksPerDay) * blocksPerDay
        let blocksSinceLastDistribution = currentBlock - lastDistributionBlock
        logger.info("TCY Reward - Last distribution block: \(lastDistributionBlock), Blocks since: \(blocksSinceLastDistribution)")

        guard blocksSinceLastDistribution > 0 else {
            // Just after distribution, use current accrued amount
            logger.info("TCY Reward - Just after distribution, using current accrued amount")
            return try await calculateUserShare(
                stakedAmount: stakedAmount,
                totalEstimatedRune: currentAccruedRune
            )
        }

        // 5. Calculate RUNE per block rate
        let runePerBlock = currentAccruedRune / Decimal(blocksSinceLastDistribution)
        logger.info("TCY Reward - RUNE per block: \(String(describing: runePerBlock))")

        // 6. Calculate total estimated RUNE by next distribution
        let additionalRune = runePerBlock * Decimal(blocksRemaining)
        let totalEstimatedRune = currentAccruedRune + additionalRune
        logger.info("TCY Reward - Total estimated RUNE: \(String(describing: totalEstimatedRune))")

        // 7. Calculate user's share
        return try await calculateUserShare(
            stakedAmount: stakedAmount,
            totalEstimatedRune: totalEstimatedRune
        )
    }

    /// Calculate user's share of the distribution based on MinRuneForTCYStakeDistribution threshold
    func calculateUserShare(stakedAmount: Decimal, totalEstimatedRune: Decimal) async throws -> Decimal {
        // Get TCY constants
        let constants = try await fetchThorchainConstants()
        logger.info("TCY User Share - MinRuneForDistribution: \(String(describing: constants.minRuneForDistribution))")

        // Calculate actual distribution amount based on MinRuneForTCYStakeDistribution
        // Only distribute in multiples of the minimum threshold (using floor)
        let rawMultiplier = totalEstimatedRune / constants.minRuneForDistribution
        let distributionMultiplier = Decimal(floor(NSDecimalNumber(decimal: rawMultiplier).doubleValue))
        let actualDistributionAmount = distributionMultiplier * constants.minRuneForDistribution
        logger.info("TCY User Share - Raw multiplier: \(String(describing: rawMultiplier)), Floor: \(String(describing: distributionMultiplier))")
        logger.info("TCY User Share - Actual distribution amount: \(String(describing: actualDistributionAmount))")

        guard actualDistributionAmount > 0 else {
            logger.warning("TCY User Share - Actual distribution amount is 0, returning 0")
            return 0
        }

        // Get total staked TCY from all stakers (not total supply)
        let totalStakedTcy = try await fetchTotalStakedTcy()
        logger.info("TCY User Share - Total staked TCY: \(String(describing: totalStakedTcy))")

        // Calculate user's share based on their TCY stake relative to total staked
        let userShare = stakedAmount / totalStakedTcy
        logger.info("TCY User Share - User staked: \(String(describing: stakedAmount)), User share: \(String(describing: userShare))")

        // Calculate user's estimated distribution amount
        let userEstimatedReward = actualDistributionAmount * userShare
        logger.info("TCY User Share - Final estimated reward: \(String(describing: userEstimatedReward))")

        return userEstimatedReward
    }

    /// Fetch total staked TCY from all stakers
    func fetchTotalStakedTcy() async throws -> Decimal {
        let target = THORChainStakingAPI.getTcyStakers
        let response = try await httpClient.request(target, responseType: TcyStakersResponse.self)

        // Sum all staked amounts
        let totalSatoshis = response.data.tcy_stakers.reduce(Decimal(0)) { sum, staker in
            let amount = Decimal(string: staker.amount) ?? 0
            return sum + amount
        }

        // Convert from satoshis to TCY
        let totalTcy = totalSatoshis / Decimal(sign: .plus, exponent: 8, significand: 1)
        return totalTcy
    }

    /// Calculate TCY APY based on user's historical distributions
    /// Logic mirrors: https://github.com/familiarcow/RUNE-Tools TCY.svelte calculateAPY
    func calculateTcyAPY(tcyCoin: Coin, runeCoin: Coin, address: String, stakedAmount: Decimal) async throws -> Double {
        // 1. Get prices using RateProvider
        let tcyPriceUSD = RateProvider.shared.rate(for: tcyCoin)?.value ?? 0
        let runePriceUSD = RateProvider.shared.rate(for: runeCoin)?.value ?? 0

        guard tcyPriceUSD > 0, runePriceUSD > 0, stakedAmount > 0 else {
            return 0
        }

        // 2. Get user-specific distributions from Midgard
        let distributionData = try await fetchTcyUserDistributions(address: address)
        let distributions = distributionData.distributions

        guard !distributions.isEmpty else {
            return 0
        }

        // 3. Calculate total RUNE received from all distributions
        let totalRune = distributions.reduce(Decimal(0)) { sum, dist in
            let amount = Decimal(string: dist.amount) ?? 0
            return sum + (amount / pow(10, 8))
        }

        // 4. Calculate average daily RUNE (total / number of distributions)
        let days = distributions.count
        let avgDailyRune = totalRune / Decimal(days)

        // 5. Annualize
        let annualRune = avgDailyRune * 365
        let annualUSD = annualRune * Decimal(runePriceUSD)

        // 6. Calculate staked value in USD
        let stakedValueUSD = stakedAmount * Decimal(tcyPriceUSD)

        // 7. Calculate APY
        let apy = stakedValueUSD > 0 ? Double(truncating: (annualUSD / stakedValueUSD) as NSDecimalNumber) * 100 : 0

        return apy
    }
}

// MARK: - Errors

enum StakingError: Error, LocalizedError {
    case unsupportedCoin
    case invalidURL
    case invalidResponse
    case missingData

    var errorDescription: String? {
        switch self {
        case .unsupportedCoin:
            return "This coin does not support staking through THORChain"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from staking API"
        case .missingData:
            return "Missing required staking data"
        }
    }
}
