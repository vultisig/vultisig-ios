//
//  CosmosTokenMetadataResolver.swift
//  VultisigApp
//
//  Cache-fronted resolver for Cosmos bank-denom metadata and IBC denom
//  traces. Mirrors the SDK `getBankDenomMetadata` fallback chain (see
//  `vultisig-sdk/packages/core/chain/coin/token/metadata/resolvers/cosmos.ts`)
//  with parity TTL (24h) and parity "share one in-flight request" semantics.
//
//  Why an `actor`: concurrent `CosmosCoinFinder` callers (balance refresh
//  fan-out, vault switch) must coalesce on a single network round-trip per
//  denom. The cache stores `Task<Value?, Error>` cells rather than settled
//  values so two awaiters of the same denom share one in-flight HTTP
//  request — same shape as the SDK's `Promise<T | null>` cache.
//
//  Failure handling: on `nil` result OR thrown error, the cache entry is
//  evicted before returning so the next call retries. A single transient
//  LCD blip must NOT poison metadata for 24h.
//

import Foundation
import OSLog

actor CosmosTokenMetadataResolver {

    static let shared = CosmosTokenMetadataResolver()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "cosmos-discovery")
    private let httpClient: HTTPClientProtocol

    /// 24h — mirrors `vultisig-sdk` denom-metadata cache TTL exactly. Long
    /// enough to absorb refresh fan-out, short enough that newly-listed bank
    /// denoms surface inside a day.
    private let cacheTTL: TimeInterval = 24 * 60 * 60

    /// Cache entry shape: holds the `Task` (not the settled value) so
    /// concurrent callers share one in-flight HTTP round-trip. `storedAt`
    /// gates expiration — TTL is measured from task creation, not from
    /// completion.
    private struct CachedTask<T> {
        let task: Task<T?, Error>
        let storedAt: Date
    }

    private var metadataCache: [String: CachedTask<CosmosDenomMetadata>] = [:]
    private var traceCache: [String: CachedTask<CosmosIbcDenomTraceDenomTrace>] = [:]

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    // MARK: - Public surface

    /// Resolve the metadata blob for a single bank denom. Tries direct
    /// fetch first, then falls back to the `?pagination.limit=1000` list.
    /// Returns `nil` when neither tier yields a hit; the caller (typically
    /// `CosmosCoinFinder`) decides whether to recurse via IBC trace or
    /// hide-with-fallback-ticker.
    func denomMetadata(chain: Chain, denom: String) async -> CosmosDenomMetadata? {
        let key = cacheKey(chain: chain, value: denom)

        if let cached = metadataCache[key], !isExpired(storedAt: cached.storedAt) {
            do {
                if let value = try await cached.task.value {
                    return value
                }
                // The shared task completed with `nil` — evict so the next
                // call can retry (matches SDK behaviour for transient LCD
                // failures).
                metadataCache.removeValue(forKey: key)
                return nil
            } catch {
                metadataCache.removeValue(forKey: key)
                return nil
            }
        }

        // Spawn-and-cache. We deliberately capture `httpClient` (not `self`)
        // inside the Task body so the work runs on the cooperative pool
        // rather than re-entering the actor while we hold the cache key.
        let httpClient = self.httpClient
        let task = Task<CosmosDenomMetadata?, Error> {
            try await Self.fetchDenomMetadata(httpClient: httpClient, chain: chain, denom: denom)
        }
        metadataCache[key] = CachedTask(task: task, storedAt: Date())

        do {
            if let value = try await task.value {
                return value
            }
            metadataCache.removeValue(forKey: key)
            return nil
        } catch {
            logger.warning("Denom metadata lookup failed for \(denom, privacy: .public) on \(chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            metadataCache.removeValue(forKey: key)
            return nil
        }
    }

    /// Resolve the IBC denom trace for a `ibc/<HASH>` denom. Returns `nil`
    /// for non-IBC denoms WITHOUT making a network call — the SDK does the
    /// same prefix check so we avoid pointless LCD traffic on factory /
    /// native denoms.
    func ibcDenomTrace(chain: Chain, denom: String) async -> CosmosIbcDenomTraceDenomTrace? {
        guard denom.hasPrefix("ibc/") else { return nil }
        let hash = String(denom.dropFirst("ibc/".count))
        guard !hash.isEmpty else { return nil }

        let key = cacheKey(chain: chain, value: denom)

        if let cached = traceCache[key], !isExpired(storedAt: cached.storedAt) {
            do {
                if let value = try await cached.task.value {
                    return value
                }
                traceCache.removeValue(forKey: key)
                return nil
            } catch {
                traceCache.removeValue(forKey: key)
                return nil
            }
        }

        let httpClient = self.httpClient
        let task = Task<CosmosIbcDenomTraceDenomTrace?, Error> {
            try await Self.fetchIbcDenomTrace(httpClient: httpClient, chain: chain, hash: hash)
        }
        traceCache[key] = CachedTask(task: task, storedAt: Date())

        do {
            if let value = try await task.value {
                return value
            }
            traceCache.removeValue(forKey: key)
            return nil
        } catch {
            logger.warning("IBC trace lookup failed for \(denom, privacy: .public) on \(chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            traceCache.removeValue(forKey: key)
            return nil
        }
    }

    /// Public test seam. Production callers use the singleton and never
    /// need to flush.
    func clearCacheForTests() {
        metadataCache.removeAll()
        traceCache.removeAll()
    }

    // MARK: - Decoders (pure)

    /// Pick the `denom_units` entry whose `denom` matches `display` (or,
    /// failing that, `symbol`) and return its `exponent`. The SDK's
    /// `decimalsFromMeta` does the same — see `cosmos.ts:18-24`. Returns
    /// `nil` when the metadata is missing the disambiguators; the caller
    /// then falls through to the next tier (IBC trace, factory derivation,
    /// or hide-with-fee-decimals fallback).
    static func decimalsFromMeta(_ meta: CosmosDenomMetadata) -> Int? {
        guard let denomUnits = meta.denomUnits, let display = meta.display else {
            return nil
        }
        // The display unit's exponent must be > 0 — a `denom_units` entry
        // with exponent 0 is the base unit, not the human-readable unit.
        if let unit = denomUnits.first(where: { $0.denom == display }), unit.exponent > 0 {
            return unit.exponent
        }
        if let symbol = meta.symbol,
           let unit = denomUnits.first(where: { $0.denom == symbol }) {
            return unit.exponent
        }
        return nil
    }

    /// Derive a human-readable ticker for a denom, preferring SDK-source
    /// metadata fields and falling through to the same factory / x-staking
    /// / IBC string-splitting tiers as `deriveTicker` in the SDK.
    static func deriveTicker(denom: String, meta: CosmosDenomMetadata?) -> String {
        if let symbol = meta?.symbol, !symbol.isEmpty {
            return symbol
        }
        if let display = meta?.display, !display.isEmpty {
            return display
        }

        if denom.hasPrefix("x/staking-") {
            let suffix = String(denom.dropFirst("x/staking-".count))
            return "S\(suffix)"
        }
        if denom.hasPrefix("x/") {
            return denom.split(separator: "/").last.map(String.init) ?? denom
        }
        if denom.hasPrefix("factory/") {
            let sub = denom.split(separator: "/").last.map(String.init) ?? denom
            return sub.hasPrefix("u") ? String(sub.dropFirst()) : sub
        }
        return denom
    }

    // MARK: - Private fetch implementations

    private static func fetchDenomMetadata(
        httpClient: HTTPClientProtocol,
        chain: Chain,
        denom: String
    ) async throws -> CosmosDenomMetadata? {
        guard let config = try? CosmosServiceConfig.getConfig(forChain: chain),
              let baseURL = config.baseURL else {
            return nil
        }

        // Tier 1: direct lookup `/denoms_metadata/{denom}`.
        if let direct = try? await httpClient.request(
            CosmosAPI(baseURL: baseURL, endpoint: .denomMetadata(denom: denom)),
            responseType: CosmosDenomMetadataResponse.self
        ).data.metadata {
            return direct
        }

        // Tier 2: enumerate `/denoms_metadata?pagination.limit=1000` and
        // match on `base == denom`. Some chains return 404 on the direct
        // path for valid denoms; the list path is the SDK's documented
        // fallback. Errors here propagate so the caller's cache eviction
        // kicks in on transient LCD failure.
        let list = try await httpClient.request(
            CosmosAPI(baseURL: baseURL, endpoint: .allDenomsMetadata),
            responseType: CosmosDenomMetadatasResponse.self
        )
        return list.data.metadatas?.first(where: { $0.base == denom })
    }

    private static func fetchIbcDenomTrace(
        httpClient: HTTPClientProtocol,
        chain: Chain,
        hash: String
    ) async throws -> CosmosIbcDenomTraceDenomTrace? {
        guard let config = try? CosmosServiceConfig.getConfig(forChain: chain),
              let baseURL = config.baseURL else {
            return nil
        }

        let response = try await httpClient.request(
            CosmosAPI(baseURL: baseURL, endpoint: .ibcDenomTrace(hash: hash)),
            responseType: CosmosIbcDenomTrace.self
        )
        return response.data.denomTrace
    }

    // MARK: - Helpers

    private func cacheKey(chain: Chain, value: String) -> String {
        "\(chain.rawValue):\(value)"
    }

    private func isExpired(storedAt: Date) -> Bool {
        Date().timeIntervalSince(storedAt) >= cacheTTL
    }
}
