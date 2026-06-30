//
//  SolanaStakingService.swift
//  VultisigApp
//
//  Read-side service for Solana native staking. Fans the four staking reads
//  (validators, stake accounts, epoch info, rent reserve) through the existing
//  `SolanaService` RPC layer and owns the validator-set / inflation caches that
//  don't belong on the per-call RPC service. Analog: `CosmosStakingService`.
//
//  Cache TTLs (per the staking spec):
//    - validator set: 10 min  -> actor `CachedEntry` (here)
//    - inflation:     10 min  -> actor `CachedEntry` (here)
//    - epoch info:    ~45 s   -> `SolanaService` (`Utils.getCachedData`)
//    - rent reserve:  24 h    -> `SolanaService` (`Utils.getCachedData`)
//    - stake accounts: NOT cached — must reflect just-submitted txs + rewards.
//

import Foundation
import OSLog

protocol SolanaStakingServiceProtocol: Sendable {
    func fetchValidators() async throws -> [SolanaValidator]
    func fetchStakeAccounts(owner: String) async throws -> [SolanaStakeAccount]
    func fetchEpochInfo() async throws -> SolanaEpochInfo
    func fetchRentReserve() async throws -> UInt64
    func fetchInflationRate() async throws -> Double
}

/// The narrow set of Solana RPC reads the staking service composes. Lets the
/// service be tested against a fake without standing up the whole RPC stack —
/// `SolanaService` is the production conformer.
protocol SolanaStakingReading {
    func fetchSolanaValidators() async throws -> [SolanaValidator]
    func fetchSolanaStakeAccounts(owner: String) async throws -> [SolanaStakeAccount]
    func fetchSolanaEpochInfo() async throws -> SolanaEpochInfo
    func fetchSolanaRentReserve() async throws -> UInt64
    func fetchSolanaInflationRate() async throws -> Double
}

extension SolanaService: SolanaStakingReading {}

actor SolanaStakingService: SolanaStakingServiceProtocol {

    /// Process-wide instance so the validator-set (10 min) and inflation (10 min)
    /// caches survive across screen opens. Consumers are per-navigation
    /// `@StateObject` view models that used to each `news-up` their own service —
    /// which threw the caches away on every open. Sharing one actor (it is
    /// `Sendable`) keeps the TTLs honest the way the epoch/rent caches on
    /// `SolanaService.shared` already do. Tests inject their own instance.
    static let shared = SolanaStakingService()

    private struct CachedEntry<Value> {
        let value: Value
        let fetchedAt: Date
    }

    private let solanaService: SolanaStakingReading
    private let validatorTTL: TimeInterval
    private let inflationTTL: TimeInterval
    private let clock: @Sendable () -> Date
    private let logger: Logger

    private var validatorCache: CachedEntry<[SolanaValidator]>?
    private var inflationCache: CachedEntry<Double>?

    init(
        solanaService: SolanaStakingReading = SolanaService.shared,
        validatorTTL: TimeInterval = 10 * 60,
        inflationTTL: TimeInterval = 10 * 60,
        clock: @escaping @Sendable () -> Date = { Date() },
        logger: Logger = Logger(subsystem: "com.vultisig.app", category: "solana-staking-service")
    ) {
        self.solanaService = solanaService
        self.validatorTTL = validatorTTL
        self.inflationTTL = inflationTTL
        self.clock = clock
        self.logger = logger
    }

    func fetchValidators() async throws -> [SolanaValidator] {
        if let cache = validatorCache, clock().timeIntervalSince(cache.fetchedAt) < validatorTTL {
            return cache.value
        }
        let validators = try await solanaService.fetchSolanaValidators()
        validatorCache = CachedEntry(value: validators, fetchedAt: clock())
        return validators
    }

    func fetchStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] {
        // Intentionally uncached — stake accounts must reflect a just-submitted
        // stake/unstake and newly accrued (auto-compounded) rewards.
        try await solanaService.fetchSolanaStakeAccounts(owner: owner)
    }

    func fetchEpochInfo() async throws -> SolanaEpochInfo {
        try await solanaService.fetchSolanaEpochInfo()
    }

    func fetchRentReserve() async throws -> UInt64 {
        try await solanaService.fetchSolanaRentReserve()
    }

    func fetchInflationRate() async throws -> Double {
        if let cache = inflationCache, clock().timeIntervalSince(cache.fetchedAt) < inflationTTL {
            return cache.value
        }
        let rate = try await solanaService.fetchSolanaInflationRate()
        inflationCache = CachedEntry(value: rate, fetchedAt: clock())
        return rate
    }
}
