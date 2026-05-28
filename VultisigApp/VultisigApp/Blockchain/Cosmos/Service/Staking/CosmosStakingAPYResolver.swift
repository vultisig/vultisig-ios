//
//  CosmosStakingAPYResolver.swift
//  VultisigApp
//
//  Actor-based resolver that fans out 4 LCD reads in parallel and folds
//  them into the chain-wide `CosmosChainApyData` consumed by per-validator
//  APY display. Caches results per chain for 5 minutes — same TTL as the
//  Windows `useCosmosChainApyQuery` React Query hook.
//
//  Fallback chain matches the Windows behavior:
//    1. Try full LCD fan-out, compute APY, display.
//    2. If any of the 4 LCD calls fails (timeout / 5xx / 404 / 501): fall
//       back to the per-chain baseline — 0.125 for LUNA (the prior iOS
//       constant), nil for LUNC (no stable post-split baseline). The view
//       layer hides the APY row when nil per the populated-card Figma.
//
//  Mirrors `getCosmosChainApyData.ts` on Windows.
//

import Foundation
import OSLog

protocol CosmosStakingAPYResolverProtocol: Sendable {
    func chainApy(chain: Chain, stakingDenom: String) async -> CosmosChainApyData?
    func baselineFallback(chain: Chain) -> Decimal?
}

actor CosmosStakingAPYResolver: CosmosStakingAPYResolverProtocol {

    private struct CachedEntry {
        let data: CosmosChainApyData
        let fetchedAt: Date
    }

    private let httpClient: HTTPClientProtocol
    private let ttl: TimeInterval
    private let clock: @Sendable () -> Date
    private let logger: Logger

    private var cache: [Chain: CachedEntry] = [:]
    /// Coalesces concurrent callers for the same chain into a single in-flight
    /// LCD fan-out — the second caller awaits the first task instead of
    /// re-issuing the 4 GETs.
    private var inFlight: [Chain: Task<CosmosChainApyData?, Never>] = [:]

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        ttl: TimeInterval = 5 * 60,
        clock: @escaping @Sendable () -> Date = { Date() },
        logger: Logger = Logger(subsystem: "com.vultisig.app", category: "cosmos-apy-resolver")
    ) {
        self.httpClient = httpClient
        self.ttl = ttl
        self.clock = clock
        self.logger = logger
    }

    /// Returns the cached or freshly-fetched chain-level APY inputs. Returns
    /// `nil` when the LCD fan-out fails — the caller should then fall back
    /// to `baselineFallback(chain:)` for the display value.
    func chainApy(chain: Chain, stakingDenom: String) async -> CosmosChainApyData? {
        if let entry = cache[chain], clock().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.data
        }
        if let task = inFlight[chain] {
            return await task.value
        }
        let task = Task<CosmosChainApyData?, Never> { [self] in
            await self.fanOut(chain: chain, stakingDenom: stakingDenom)
        }
        inFlight[chain] = task
        let result = await task.value
        inFlight[chain] = nil
        if let result {
            cache[chain] = CachedEntry(data: result, fetchedAt: clock())
        }
        return result
    }

    /// Per-chain APY fallback used when the LCD fan-out fails. Mirrors the
    /// prior iOS baseline shape — 12.5% for LUNA, nil for LUNC.
    nonisolated func baselineFallback(chain: Chain) -> Decimal? {
        switch chain {
        case .terra:
            return Decimal(string: "0.125")
        default:
            return nil
        }
    }

    // MARK: - Fan-out

    private func fanOut(chain: Chain, stakingDenom: String) async -> CosmosChainApyData? {
        do {
            let baseURL = try CosmosStakingAPYResolver.baseURL(for: chain)
            async let inflationTask = fetchInflation(baseURL: baseURL)
            async let poolTask = fetchPool(baseURL: baseURL)
            async let supplyTask = fetchSupply(baseURL: baseURL, denom: stakingDenom)
            async let paramsTask = fetchParams(baseURL: baseURL)

            let (inflation, pool, supply, params) = try await (
                inflationTask,
                poolTask,
                supplyTask,
                paramsTask
            )

            let bondedRatio: Decimal
            if supply > 0 {
                bondedRatio = Self.clamp01(pool / supply)
            } else {
                bondedRatio = 0
            }
            return CosmosChainApyData(
                inflation: Self.clamp01(inflation),
                bondedRatio: bondedRatio,
                communityTax: Self.clamp01(params)
            )
        } catch {
            logger.warning(
                "Chain APY fan-out failed for \(chain.rawValue, privacy: .public) — falling back to baseline: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func fetchInflation(baseURL: URL) async throws -> Decimal {
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .mintInflation),
            responseType: CosmosMintInflationResponse.self
        )
        return Decimal(string: response.data.inflation) ?? 0
    }

    private func fetchPool(baseURL: URL) async throws -> Decimal {
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .stakingPool),
            responseType: CosmosStakingPoolResponse.self
        )
        return Decimal(string: response.data.pool.bondedTokens) ?? 0
    }

    private func fetchSupply(baseURL: URL, denom: String) async throws -> Decimal {
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .bankSupplyByDenom(denom: denom)),
            responseType: CosmosBankSupplyResponse.self
        )
        return Decimal(string: response.data.amount.amount) ?? 0
    }

    private func fetchParams(baseURL: URL) async throws -> Decimal {
        let response = try await httpClient.request(
            CosmosStakingAPI(baseURL: baseURL, endpoint: .distributionParams),
            responseType: CosmosDistributionParamsResponse.self
        )
        return Decimal(string: response.data.params.communityTax) ?? 0
    }

    // MARK: - Helpers

    /// Per-validator multiplier — `(1 - communityTax) × (inflation /
    /// bondedRatio) × (1 - commission)`. Collapses to `nil` when inflation
    /// or bonded ratio is zero so the view layer can hide the row.
    static func computeValidatorAPY(
        chainData: CosmosChainApyData,
        commission: Decimal
    ) -> Decimal? {
        let inflation = clamp01(chainData.inflation)
        let bondedRatio = chainData.bondedRatio
        guard inflation > 0, bondedRatio > 0 else { return nil }
        let communityTax = clamp01(chainData.communityTax)
        let commissionClamped = clamp01(commission)
        let chainBase = (1 - communityTax) * (inflation / bondedRatio)
        let apy = chainBase * (1 - commissionClamped)
        return apy > 0 ? apy : nil
    }

    private static func clamp01(_ value: Decimal) -> Decimal {
        if value < 0 { return 0 }
        if value > 1 { return 1 }
        return value
    }

    private static func baseURL(for chain: Chain) throws -> URL {
        let config = try CosmosServiceConfig.getConfig(forChain: chain)
        guard let url = config.baseURL else {
            throw CosmosStakingConfigError.unsupportedChain(chain)
        }
        return url
    }
}
