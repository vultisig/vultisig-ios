//
//  THORChainStakingService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/10/2025.
//

import BigInt
import Foundation
import OSLog

/// Read side of THORChain ecosystem staking, abstracted so callers can be driven
/// without the network. `THORChainStakingService.shared` is the production
/// implementation.
protocol THORChainStakingProviding {
    func fetchStakingDetails(coinMeta: CoinMeta, runeCoinMeta: CoinMeta, address: String) async throws -> StakingDetails
}

/// Service for fetching staking details for THORChain ecosystem coins (RUJI and TCY)
class THORChainStakingService: THORChainStakingProviding {
    static let shared = THORChainStakingService()

    private let httpClient: HTTPClient
    private let logger = Log.chain.other

    // Cache for TCY constants (they don't change often)
    private var cachedTcyConstants: TcyConstants?
    private var constantsCacheTimestamp: Date?
    private let constantsCacheDuration: TimeInterval = 3600 // 1 hour
    private let thorchainAPIService = THORChainAPIService()

    private init() {
        httpClient = HTTPClient()
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
    ///   - coinMeta: Metadata of the coin being staked (value type — `@Model` Coin must not cross
    ///     actor boundaries here)
    ///   - runeCoinMeta: RUNE coin metadata for price lookups
    ///   - address: The THORChain address
    /// - Returns: StakingDetails with amount, APR, rewards, etc.
    func fetchStakingDetails(coinMeta: CoinMeta, runeCoinMeta: CoinMeta, address: String) async throws -> StakingDetails {
        switch coinMeta.ticker.uppercased() {
        case "RUJI", "SRUJI":
            // One pool, two positions: the bonded amount and the auto-compounding
            // amount both come from the same account query, so the sRUJI receipt
            // resolves against the RUJI pool rather than a pool of its own.
            return try await fetchRujiStakingDetails(address: address)
        case "TCY":
            return try await fetchTcyStakingDetails(coinMeta: coinMeta, runeCoinMeta: runeCoinMeta, address: address)
        default:
            throw StakingError.unsupportedCoin
        }
    }
}

// MARK: - RUJI Implementation

private extension THORChainStakingService {
    /// Fetch RUJI staking details from GraphQL API
    func fetchRujiStakingDetails(address: String) async throws -> StakingDetails {
        let target = THORChainStakingAPI.getRujiStaking(address: address)
        let response = try await httpClient.request(target, responseType: AccountRootData.self)
        return try Self.makeRujiStakingDetails(from: response.data)
    }
}

extension THORChainStakingService {
    /// Translates a Rujira account payload into `StakingDetails`, selecting the
    /// RUJI pool and scaling every amount out of base units.
    ///
    /// Pure so the parse is unit-testable without the network round-trip, the
    /// same way `ThorchainService.parseStakingReceiptAmount` is.
    static func makeRujiStakingDetails(from decoded: AccountRootData) throws -> StakingDetails {
        // Distinguish "address has no RUJI stake" (genuine empty) from "response is missing /
        // partial" (don't trust it). Returning `.empty` for the latter caused persisted RUJI
        // positions to be silently overwritten with zero on stale GraphQL responses.
        guard let node = decoded.data.node else {
            throw StakingError.invalidResponse
        }
        guard let stakingV2 = node.stakingV2 else {
            throw StakingError.invalidResponse
        }
        // `stakingV2` carries an entry per Rujira staking pool the account touches,
        // and the first is not guaranteed to be RUJI. Select by bond-asset symbol.
        guard let stake = stakingV2.first(where: {
            $0.bonded.asset.metadata?.symbol.uppercased() == "RUJI"
        }) else {
            // The address has staking entries but none for RUJI — genuine zero stake.
            return .empty
        }

        // Parse the bonded amount — the position that accrues claimable USDC. An
        // unparseable value is a partial response, not an empty position, and a
        // spurious zero here is precisely what disables Unstake on a funded card.
        guard let stakedAmount = BigInt(stake.bonded.amount),
              let stakedDecimal = Decimal(string: stakedAmount.description) else {
            throw StakingError.invalidResponse
        }
        let stakedFinal = stakedDecimal / pow(10, 8) // RUJI has 8 decimals

        // Parse the auto-compounding amount. `liquidSize` is the sRUJI receipt
        // valued in RUJI at the pool's current share price, which is what the
        // Rujira app shows; the raw on-chain receipt balance is a share count and
        // would understate the position. Independent of `bonded` — an account can
        // hold both — so this never falls back to it.
        //
        // The field is non-null in the Rujira schema and is the only source for the
        // auto-compounding position, so a missing or unparseable value means a
        // partial response, not an empty position. Fail closed like the guards
        // above rather than report a zero that would erase a live position.
        guard let liquidSize = stake.liquidSize,
              let liquidSizeRaw = liquidSize.amount,
              let liquidSizeAmount = BigInt(liquidSizeRaw),
              let liquidSizeDecimal = Decimal(string: liquidSizeAmount.description) else {
            throw StakingError.invalidResponse
        }
        let liquidSizeFinal = liquidSizeDecimal / pow(10, 8)

        // Parse the claimable revenue. Lenient on purpose, unlike the two amounts
        // above: revenue is a CTA on an otherwise-complete card, so losing it must
        // not take the position balances down with it.
        let rewardsAmount = BigInt(stake.pendingRevenue?.amount ?? "0") ?? .zero
        let rewardsDecimal = Decimal(string: rewardsAmount.description) ?? 0
        let rewardsFinal = rewardsDecimal / pow(10, 8) // THORChain normalizes all assets to 8 decimals

        // Parse APR. The fractional-rate conversion (12-decimal Bigint → e.g. 0.0116 for
        // 1.16%) lives on the model itself; see `AccountRootData...APR.fractionalRate`.
        let apr: Double? = stake.pool?.summary?.apr?.fractionalRate

        // USDC coin meta for the claimable revenue
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
            autoCompoundAmount: liquidSizeFinal,
            apr: apr,
            estimatedReward: nil, // Not available for RUJI
            nextPayoutDate: nil, // Not available for RUJI
            rewards: rewardsFinal,
            rewardsCoin: usdcCoin
        )
    }
}

// MARK: - TCY Implementation

private extension THORChainStakingService {
    /// Fetch TCY staking details
    func fetchTcyStakingDetails(coinMeta: CoinMeta, runeCoinMeta: CoinMeta, address: String) async throws -> StakingDetails {
        // 1. Fetch staked amount
        let stakedResponse = try await fetchTcyStakedAmount(address: address)
        let stakedAmount = Decimal(string: stakedResponse.amount) ?? 0
        let stakedDecimal = stakedAmount / Decimal(sign: .plus, exponent: 8, significand: 1) // Divide by 10^8 using Decimal
        logger.info("TCY Staking - Raw: \(stakedResponse.amount), Decimal: \(String(describing: stakedAmount)), Final: \(String(describing: stakedDecimal))")

        // 2. Calculate APY and convert to APR
        let apy = try await calculateTcyAPY(tcyCoinMeta: coinMeta, runeCoinMeta: runeCoinMeta, address: address, stakedAmount: stakedDecimal)
        let apr = convertAPYtoAPR(apy)

        // 3. Calculate next payout
        let nextPayout = try await calculateTcyNextPayout()

        // 4. Calculate estimated reward
        let estimatedReward = try await calculateTcyEstimatedReward(stakedAmount: stakedDecimal)

        return StakingDetails(
            stakedAmount: stakedDecimal,
            autoCompoundAmount: 0, // TCY's auto-compound side is read on-chain, not here
            apr: apr,
            estimatedReward: estimatedReward,
            nextPayoutDate: nextPayout,
            rewards: nil, // TCY auto-distributes, no pending rewards
            rewardsCoin: TokensStore.rune
        )
    }

    /// ⚠️ **An address that holds no TCY stake is an ANSWER, not a failure.**
    ///
    /// THORNode answers `/thorchain/tcy_staker/<addr>` for a non-staker with a
    /// **500** — `fail to tcy staker: TCYStaker doesn't exist: thor1…` — so
    /// "you have no position" and "the node broke" arrive with the same status
    /// code, and the body is the only thing separating them. Left to throw, the
    /// interactor returns no positions, storage upserts nothing, and the card
    /// keeps the balance the user just withdrew — the position reads as still
    /// staked until something else happens to refresh it.
    ///
    /// Only the absence is swallowed. Every other failure still throws, because
    /// the persisted row keeping its last good value is the right answer to a
    /// read that did not happen, and zeroing a funded position on a transient
    /// fault is the more expensive mistake — the same reasoning
    /// `makeRujiStakingDetails` records for its own empty-versus-partial split.
    func fetchTcyStakedAmount(address: String) async throws -> TcyStakerResponse {
        let target = THORChainStakingAPI.getTcyStakedAmount(address: address)
        do {
            let response = try await httpClient.request(target, responseType: TcyStakerResponse.self)
            return response.data
        } catch {
            guard Self.isTcyStakerAbsent(error) else { throw error }
            return TcyStakerResponse(amount: "0")
        }
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
        let dailyRate = pow(1 + apyDecimal, 1.0 / 365.0) - 1

        return dailyRate * 365
    }

    /// Calculate next TCY payout time
    /// Distributions happen every 14,400 blocks (~24 hours at 6 seconds per block)
    func calculateTcyNextPayout() async throws -> TimeInterval {
        // 1. Get current block height
        let currentBlock = try await thorchainAPIService.getLastBlock()

        // 2. Distributions happen every 14,400 blocks
        let blocksPerDay: Int64 = 14400
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
        let blocksPerDay: UInt64 = 14400
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
        return totalSatoshis / Decimal(sign: .plus, exponent: 8, significand: 1)
    }

    /// Calculate TCY APY based on user's historical distributions
    /// Logic mirrors: https://github.com/familiarcow/RUNE-Tools TCY.svelte calculateAPY
    func calculateTcyAPY(tcyCoinMeta: CoinMeta, runeCoinMeta: CoinMeta, address: String, stakedAmount: Decimal) async throws -> Double {
        // 1. Get prices using RateProvider — uses the CoinMeta overload to keep `@Model` Coin
        // out of this off-MainActor branch.
        let tcyPriceUSD = RateProvider.shared.rate(for: tcyCoinMeta)?.value ?? 0
        let runePriceUSD = RateProvider.shared.rate(for: runeCoinMeta)?.value ?? 0

        guard tcyPriceUSD > 0, runePriceUSD > 0, stakedAmount > 0 else {
            return 0
        }

        // 2. Get user-specific distributions from Midgard
        let distributionData = try await fetchTcyUserDistributions(address: address)
        let distributions = distributionData.distributions ?? []

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
        return stakedValueUSD > 0 ? Double(truncating: (annualUSD / stakedValueUSD) as NSDecimalNumber) * 100 : 0
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

// MARK: - Reading THORNode's "no such staker"

extension THORChainStakingService {

    /// Whether an error is THORNode saying the address holds no TCY stake.
    ///
    /// ⚠️ **Matched on the body's marker rather than on the status code**, and
    /// deliberately not on the code alone: every server fault on this route is
    /// also a 500, so keying on the status would turn an outage into a zeroed
    /// position. The status is left out of the match entirely — the marker is
    /// the signal, and requiring 500 beside it only adds a second thing that
    /// can drift if THORNode ever answers this with a 404.
    ///
    /// It is a server-authored English string, so this is a narrow contract with
    /// an upstream that has not promised to keep it. A spelling change costs the
    /// stale card back, not a wrong balance.
    static func isTcyStakerAbsent(_ error: Error) -> Bool {
        guard case HTTPError.statusCode(_, let body) = error,
              let body,
              let text = String(data: body, encoding: .utf8) else {
            return false
        }
        return text.contains("TCYStaker doesn't exist")
    }
}
