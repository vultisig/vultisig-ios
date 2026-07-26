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

/// Validated CW20 token metadata as answered by a `{"token_info":{}}` wasm
/// smart query: the fields a custom-token flow needs to build a `CoinMeta`.
struct CosmosCw20TokenInfo: Equatable {
    let name: String
    let symbol: String
    let decimals: Int
}

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
    private var ibcDenomCache: [String: CachedTask<String>] = [:]
    private var cw20Cache: [String: CachedTask<CosmosCw20TokenInfo>] = [:]

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

    /// Resolve the base denom behind an `ibc/<HASH>` voucher via the modern
    /// ibc-go `/ibc/apps/transfer/v1/denoms/{hash}` endpoint. Unlike the
    /// deprecated `denom_traces/{hash}` path (which Terra Classic LCDs answer
    /// with `code 12 Not Implemented`), this endpoint is implemented on Terra
    /// Classic, so it's the resolution path the caller uses there.
    ///
    /// Returns `nil` for non-IBC denoms WITHOUT a network call (same prefix
    /// guard as `ibcDenomTrace`), and `nil` when the voucher is unknown
    /// (NotFound decodes to a nil base). Cache-coalesced exactly like
    /// `ibcDenomTrace`: concurrent callers share one in-flight round-trip and
    /// a `nil`/error result is evicted so the next call retries.
    func ibcDenom(chain: Chain, denom: String) async -> String? {
        guard denom.hasPrefix("ibc/") else { return nil }
        let hash = String(denom.dropFirst("ibc/".count))
        guard !hash.isEmpty else { return nil }

        let key = cacheKey(chain: chain, value: denom)

        if let cached = ibcDenomCache[key], !isExpired(storedAt: cached.storedAt) {
            do {
                if let value = try await cached.task.value {
                    return value
                }
                ibcDenomCache.removeValue(forKey: key)
                return nil
            } catch {
                ibcDenomCache.removeValue(forKey: key)
                return nil
            }
        }

        let httpClient = self.httpClient
        let task = Task<String?, Error> {
            try await Self.fetchIbcDenomBase(httpClient: httpClient, chain: chain, hash: hash)
        }
        ibcDenomCache[key] = CachedTask(task: task, storedAt: Date())

        do {
            if let value = try await task.value {
                return value
            }
            ibcDenomCache.removeValue(forKey: key)
            return nil
        } catch {
            logger.warning("IBC denom lookup failed for \(denom, privacy: .public) on \(chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            ibcDenomCache.removeValue(forKey: key)
            return nil
        }
    }

    /// Resolve CW20 token metadata (`name`, `symbol`, `decimals`) for a wasm
    /// contract via the `{"token_info":{}}` smart query — the same lookup the
    /// SDK's `getCw20MetaFromLCD` performs.
    ///
    /// Returns `nil` only when the address is *definitively* not a CW20 token:
    /// the LCD rejects the smart query (wallet addresses, non-CW20 contracts,
    /// unknown addresses) or the reply fails token_info validation. Transport
    /// failures — rate limiting (HTTP 429), network errors, timeouts — THROW
    /// instead: they say nothing about the address, and the caller's error UX
    /// (rate-limit copy, retry) must not collapse into "token not found".
    /// Failures are never cached either way: the entry is evicted so the next
    /// call retries.
    func cw20TokenInfo(chain: Chain, contractAddress: String) async throws -> CosmosCw20TokenInfo? {
        let key = cacheKey(chain: chain, value: contractAddress)

        if let cached = cw20Cache[key], !isExpired(storedAt: cached.storedAt) {
            do {
                if let value = try await cached.task.value {
                    return value
                }
                cw20Cache.removeValue(forKey: key)
                return nil
            } catch {
                cw20Cache.removeValue(forKey: key)
                throw error
            }
        }

        let httpClient = self.httpClient
        let task = Task<CosmosCw20TokenInfo?, Error> {
            try await Self.fetchCw20TokenInfo(httpClient: httpClient, chain: chain, contractAddress: contractAddress)
        }
        cw20Cache[key] = CachedTask(task: task, storedAt: Date())

        do {
            if let value = try await task.value {
                return value
            }
            cw20Cache.removeValue(forKey: key)
            return nil
        } catch {
            logger.warning("CW20 token_info lookup failed for \(contractAddress, privacy: .public) on \(chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            cw20Cache.removeValue(forKey: key)
            throw error
        }
    }

    // MARK: - Decoders (pure)

    /// Mirrors the SDK's `decimalsFromMeta` byte-for-byte — see
    /// `vultisig-sdk/packages/core/chain/coin/token/metadata/resolvers/
    /// cosmos.ts` (the `decimalsFromMeta` helper). The SDK guards on both
    /// `denom_units` and `display`, then does a single `meta.symbol ||
    /// meta.display` coalesce to pick the lookup key. iOS used to deviate
    /// (display-first lookup with `exponent > 0`, symbol as fallback) which
    /// broke when a chain populated `symbol` to a different key than
    /// `display` — most Terra IBC denoms publish `symbol` as the canonical
    /// disambiguator. Mirroring the SDK keeps Terra discovery consistent
    /// across iOS / Windows / agent.
    static func decimalsFromMeta(_ meta: CosmosDenomMetadata) -> Int? {
        guard let denomUnits = meta.denomUnits, let display = meta.display else {
            return nil
        }
        let lookupKey = meta.symbol ?? display
        return denomUnits.first(where: { $0.denom == lookupKey })?.exponent
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
        if denom.hasPrefix("ibc/") {
            // Guaranteed layout fallback for an unresolved voucher: a short
            // `IBC-<6 hex>` label instead of the raw 64-char hash. Mirrors
            // Android `String.toCosmosTicker` (`IBC-` + 6-char uppercase
            // preview) so the three clients degrade to the same label.
            let hash = denom.dropFirst("ibc/".count)
            if !hash.isEmpty {
                return "IBC-" + hash.prefix(6).uppercased()
            }
        }
        // Plain bank denom: strip a leading `u`/`a` micro-unit prefix and
        // uppercase, so Terra fiat micro-denoms read as symbols
        // (`ucny` -> `CNY`, `uluna` -> `LUNA`) instead of the raw `ucny`. This
        // tier only runs for the Cosmos discovery path (`CosmosCoinFinder`,
        // allowlisted to Terra / TerraClassic), so the strip is Terra-scoped.
        return stripMicroUnitPrefix(denom).uppercased()
    }

    /// Strip a single leading micro-unit prefix (`u`/`a`) from a denom, but
    /// only when the second character is a letter — so genuine micro-denoms
    /// (`uatom`, `aevmos`) are stripped while `u123`-style ids are left
    /// intact. Does NOT uppercase. Mirrors Android `stripDenomUnitPrefix`.
    private static func stripMicroUnitPrefix(_ denom: String) -> String {
        let unitPrefixes: Set<Character> = ["u", "a"]
        guard denom.count > 1,
              let first = denom.first,
              unitPrefixes.contains(first),
              denom[denom.index(after: denom.startIndex)].isLetter else {
            return denom
        }
        return String(denom.dropFirst())
    }

    /// Derive a display ticker from an IBC voucher's resolved base denom, or
    /// `nil` when the base is opaque (an EVM `0x…` address, a namespaced denom,
    /// or too long to read as a symbol) — the caller then degrades the voucher
    /// to a short `IBC-<6hex>` label. Mirrors the SDK / Android IBC-ticker
    /// conventions:
    ///   - `factory/<minter>/<sub>` -> `<sub>` (single leading `u` stripped),
    ///     uppercased (`…/alloyed/allBTC` -> `ALLBTC`).
    ///   - a leading `u`/`a` micro-unit prefix -> stripped + uppercased
    ///     (`uusdc` -> `USDC`, `uatom` -> `ATOM`).
    ///   - an already-clean short symbol (`[A-Za-z0-9-]{1,12}`, not `0x…`)
    ///     -> uppercased (`wbnb-wei` -> `WBNB-WEI`).
    ///   - anything else (EVM address, contains `/`, too long) -> `nil`.
    static func ibcTicker(baseDenom: String) -> String? {
        // Reduce the base to a candidate symbol: a `factory/<minter>/<sub>`
        // base uses its last path segment (single leading `u` stripped), a
        // `u`/`a` micro-denom is stripped, otherwise the base stands as-is.
        let candidate: String
        if baseDenom.hasPrefix("factory/") {
            let sub = baseDenom.split(separator: "/").last.map(String.init) ?? baseDenom
            candidate = sub.hasPrefix("u") ? String(sub.dropFirst()) : sub
        } else {
            candidate = stripMicroUnitPrefix(baseDenom)
        }

        // Accept only a clean short symbol; reject opaque values (EVM `0x…`
        // addresses, anything containing `/`, over-long tails) so the caller
        // degrades the voucher to a short `IBC-<6hex>` label instead.
        guard !candidate.lowercased().hasPrefix("0x"),
              candidate.range(of: "^[A-Za-z0-9-]{1,12}$", options: .regularExpression) != nil else {
            return nil
        }
        return candidate.uppercased()
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

    /// Upper bound on accepted CW20 `decimals`. The value is contract-
    /// controlled (untrusted), and downstream formatting computes
    /// `BigInt(10).power(decimals)` — the same reason the ERC-20 metadata
    /// resolver bounds decimals to this range. The CW20 spec types decimals
    /// as `u8` and 18 is the de-facto ceiling for real tokens.
    private static let cw20DecimalsRange = 0...36

    /// HTTP statuses that signal a transient gateway/overload condition
    /// rather than a verdict on the queried contract: request timeout, too
    /// early, rate limited, bad gateway, service unavailable, gateway
    /// timeout. These rethrow so the caller can show a retryable error.
    /// Notably 500 is NOT here: Terra LCDs answer the smart query with 500
    /// for wallet addresses and non-CW20 contracts, so it means not-found.
    private static let transientHTTPStatuses: Set<Int> = [408, 425, 429, 502, 503, 504]

    /// Fetches and validates a CW20 `token_info` response. Mirrors the SDK's
    /// validation: the symbol must be non-empty after trimming and the
    /// decimals an integer within ``cw20DecimalsRange``, otherwise the
    /// contract is treated as not-a-CW20-token (`nil`). LCD error statuses
    /// outside ``transientHTTPStatuses`` and unparseable replies also mean
    /// not-a-CW20-token — that is how the LCD answers the smart query for
    /// wallet addresses and non-CW20 contracts. Transient statuses and
    /// network-layer errors propagate: they are transport failures, not a
    /// verdict on the address.
    private static func fetchCw20TokenInfo(
        httpClient: HTTPClientProtocol,
        chain: Chain,
        contractAddress: String
    ) async throws -> CosmosCw20TokenInfo? {
        guard let config = try? CosmosServiceConfig.getConfig(forChain: chain),
              let baseURL = config.baseURL else {
            return nil
        }

        let response: HTTPResponse<CosmosCw20TokenInfoResponse>
        do {
            response = try await httpClient.request(
                CosmosAPI(baseURL: baseURL, endpoint: .wasmTokenInfo(contractAddress: contractAddress)),
                responseType: CosmosCw20TokenInfoResponse.self
            )
        } catch HTTPError.statusCode(let code, let data) {
            guard !transientHTTPStatuses.contains(code) else {
                throw HTTPError.statusCode(code, data)
            }
            return nil
        } catch HTTPError.decodingFailed {
            return nil
        }

        let info = response.data.data
        guard let symbol = info.symbol?.trimmingCharacters(in: .whitespacesAndNewlines),
              !symbol.isEmpty,
              let decimals = info.decimals, cw20DecimalsRange.contains(decimals) else {
            return nil
        }

        let name = info.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CosmosCw20TokenInfo(
            name: name.isEmpty ? symbol : name,
            symbol: symbol,
            decimals: decimals
        )
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

    private static func fetchIbcDenomBase(
        httpClient: HTTPClientProtocol,
        chain: Chain,
        hash: String
    ) async throws -> String? {
        guard let config = try? CosmosServiceConfig.getConfig(forChain: chain),
              let baseURL = config.baseURL else {
            return nil
        }

        let response: HTTPResponse<CosmosIbcDenom>
        do {
            response = try await httpClient.request(
                CosmosAPI(baseURL: baseURL, endpoint: .ibcDenom(hash: hash)),
                responseType: CosmosIbcDenom.self
            )
        } catch HTTPError.statusCode(let code, let data) {
            // A NotFound voucher answers with gRPC NOT_FOUND (HTTP 404, body
            // `{"code":5,"message":"...not found..."}`). Treat any non-transient
            // status as "voucher unknown" -> nil so the caller degrades to the
            // truncated-ticker fallback. Transient gateway/overload statuses
            // rethrow so the resolver's cache eviction retries them. Same
            // discipline as `fetchCw20TokenInfo`.
            guard !transientHTTPStatuses.contains(code) else {
                throw HTTPError.statusCode(code, data)
            }
            return nil
        } catch HTTPError.decodingFailed {
            return nil
        }

        // A resolved voucher with an empty/absent base is also unresolved.
        guard let base = response.data.denom?.base, !base.isEmpty else {
            return nil
        }
        return base
    }

    // MARK: - Helpers

    private func cacheKey(chain: Chain, value: String) -> String {
        "\(chain.rawValue):\(value)"
    }

    private func isExpired(storedAt: Date) -> Bool {
        Date().timeIntervalSince(storedAt) >= cacheTTL
    }
}
