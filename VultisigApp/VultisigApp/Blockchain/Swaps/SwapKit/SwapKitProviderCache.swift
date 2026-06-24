//
//  SwapKitProviderCache.swift
//  VultisigApp
//
//  Caches the `GET /v3/providers` response (24h TTL per design §4) and
//  derives a programmatic `isEnabled(chain:)` predicate from each provider's
//  `enabledChainIds`. Routes through THORChain / MayaChain are excluded from
//  the eligibility decision — SwapKit lists those providers but Vultisig
//  filters them client-side.
//

import Foundation

/// Single provider entry from `/v3/providers`.
struct SwapKitProvider: Codable, Hashable {
    let name: String
    let provider: String
    let displayName: String?
    let displayNameLong: String?
    let count: Int?
    let enabledChainIds: [String]
    let supportedChainIds: [String]?
    let supportedActions: [String]?
}

/// Snapshot of the providers list at a point in time. Persisted with its
/// fetch timestamp so callers can compare against `SwapKitConfig.providerCacheTTL`.
struct SwapKitProvidersSnapshot {
    let providers: [SwapKitProvider]
    let fetchedAt: Date
}

actor SwapKitProviderCache {
    static let shared = SwapKitProviderCache()

    /// Single-key cache — the providers list isn't partitioned, so one fixed
    /// key holds the whole snapshot.
    private enum CacheKey { case providers }

    private let httpClient: HTTPClientProtocol
    private let cache = TTLCache<CacheKey, [SwapKitProvider]>()

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Returns a cached or freshly-fetched provider list, refreshing when the
    /// snapshot is older than `SwapKitConfig.providerCacheTTL`. Returns `nil`
    /// when the fetch fails *and* we have no prior snapshot. Callers choose
    /// their own fallback policy for that edge: `isEnabled` fails closed for
    /// offer gating, while `isPairSupported` fails open for error-label
    /// remapping.
    func providers(now: Date = Date()) async -> [SwapKitProvider]? {
        do {
            return try await cache.value(
                for: .providers,
                now: now,
                ttl: SwapKitConfig.providerCacheTTL
            ) { [httpClient] in
                let response = try await httpClient.request(
                    SwapKitAPI.providers,
                    responseType: [SwapKitProvider].self
                )
                return response.data
            }
        } catch {
            return await cache.peek(.providers)
        }
    }

    /// Synchronous variant for tests + offline computation. Caller supplies
    /// the providers list (e.g. decoded from a fixture).
    nonisolated static func chainEnabled(
        _ chain: Chain,
        in providers: [SwapKitProvider]
    ) -> Bool {
        let chainId = SwapKitChainIDMapper.swapKitChainId(for: chain)
        return providers.contains { provider in
            // Normalize before comparison — `SwapKitConfig.filteredProviders`
            // is upper-case but the upstream API has historically returned
            // mixed casing for some providers (e.g. `THORCHAIN_STREAMING` vs
            // `thorchain_streaming`). Lower-casing the filter set could
            // silently let a route slip through, so normalize the API value
            // instead.
            guard !SwapKitConfig.filteredProviders.contains(provider.provider.uppercased()) else {
                return false
            }
            return provider.enabledChainIds.contains(chainId)
        }
    }

    /// Async variant — refreshes the cache and returns whether the chain has
    /// at least one non-filtered provider enabled. Fails CLOSED (`false`) when
    /// the providers list can't be loaded at all (a cold-launch `/providers`
    /// fetch failure with no prior snapshot): SwapKit is simply not offered for
    /// the chain until a refresh succeeds, rather than offering routes that
    /// will fail downstream. Other providers still populate the picker, and
    /// `SwapService.fetchSwapKitQuote` throws `providerNotEnabled` cleanly.
    /// Once a snapshot exists, `providers(now:)` serves it as last-good on a
    /// later fetch failure, so this only bites the genuine no-data edge.
    ///
    /// Note the asymmetry with `isPairSupported(...)`, which fails OPEN on the
    /// same edge: that predicate only governs an error-label re-mapping, so
    /// failing it closed would merely degrade a message, not block a swap.
    func isEnabled(chain: Chain, now: Date = Date()) async -> Bool {
        guard let providers = await providers(now: now) else { return false }
        return Self.chainEnabled(chain, in: providers)
    }

    /// Synchronous variant for tests + offline computation. Returns `true`
    /// iff at least one non-filtered provider entry's `enabledChainIds`
    /// contains BOTH the source and destination chain ids. The intersection
    /// requirement on the same provider entry — rather than a union across
    /// providers — narrows the false-positive surface when re-classifying
    /// `noRoutesFound` errors as below-minimum amounts: a provider that
    /// enables both chains is far more likely to actually route between
    /// them than two providers that each only handle one side.
    nonisolated static func pairEnabled(
        fromChain: Chain,
        toChain: Chain,
        in providers: [SwapKitProvider]
    ) -> Bool {
        let fromId = SwapKitChainIDMapper.swapKitChainId(for: fromChain)
        let toId = SwapKitChainIDMapper.swapKitChainId(for: toChain)
        guard !fromId.isEmpty, !toId.isEmpty else { return false }
        return providers.contains { provider in
            guard !SwapKitConfig.filteredProviders.contains(provider.provider.uppercased()) else {
                return false
            }
            return provider.enabledChainIds.contains(fromId)
                && provider.enabledChainIds.contains(toId)
        }
    }

    /// Async variant — refreshes the cache and returns whether the (from, to)
    /// chain pair has at least one non-filtered provider that enables both
    /// chains. Returns `true` when the providers list can't be loaded
    /// (fail-OPEN) — the caller treats this as "could plausibly be supported"
    /// when re-classifying error codes.
    ///
    /// This deliberately differs from `isEnabled(chain:)`, which fails CLOSED
    /// on the same no-snapshot edge. The asymmetry is intentional: `isEnabled`
    /// gates whether SwapKit is *offered* at all, so the safe default is to
    /// withhold it; `isPairSupported` only chooses between two error labels
    /// (a `noRoutesFound` 404 re-mapped to `amountBelowProviderMinimum`), so
    /// failing it closed would merely show a less specific error message
    /// rather than prevent a bad swap — not worth withholding the better label.
    func isPairSupported(fromChain: Chain, toChain: Chain, now: Date = Date()) async -> Bool {
        guard let providers = await providers(now: now) else { return true }
        return Self.pairEnabled(fromChain: fromChain, toChain: toChain, in: providers)
    }

    /// Replace the snapshot — exposed for tests so they don't have to stand
    /// up a fake HTTPClient.
    func setSnapshot(_ snapshot: SwapKitProvidersSnapshot) async {
        await cache.setCached(snapshot.providers, for: .providers, fetchedAt: snapshot.fetchedAt)
    }
}

/// Maps Vultisig's `Chain` enum to SwapKit's chainId string (per
/// `api-contract.md` canonical chain table). Returns `""` when the chain has
/// no SwapKit-side identifier — that maps to "definitely not enabled" in the
/// cache predicate, which is what we want.
enum SwapKitChainIDMapper {
    static func swapKitChainId(for chain: Chain) -> String {
        switch chain {
        case .ethereum: return "1"
        case .arbitrum: return "42161"
        case .avalanche: return "43114"
        case .base: return "8453"
        case .bscChain: return "56"
        case .polygon, .polygonV2: return "137"
        case .optimism: return "10"
        case .solana: return "solana"
        case .bitcoin: return "bitcoin"
        case .bitcoinCash: return "bitcoincash"
        case .litecoin: return "litecoin"
        case .dogecoin: return "dogecoin"
        case .dash: return "dash"
        case .zcash: return "zcash"
        case .tron: return "728126428"
        case .ton: return "ton"
        case .cardano: return "cardano"
        case .sui: return "sui"
        case .ripple: return "ripple"
        case .gaiaChain: return "cosmoshub-4"
        case .kujira: return "kaiyo-1"
        case .mayaChain: return "mayachain-mainnet-v1"
        case .thorChain, .thorChainChainnet, .thorChainStagenet: return "thorchain-1"
        default: return ""
        }
    }

    /// Reverse map for the per-token `chain` field in `/tokens` responses
    /// (uppercase ticker-style key, e.g. `"ETH"`, `"BSC"`, `"NEAR"`, `"BTC"`).
    /// Returns `nil` for chains Vultisig has no wallet support for — those
    /// tokens can't be receive destinations so they're dropped at decode.
    /// Note: SwapKit's per-token `chain` is unique per Vultisig chain (Base
    /// ETH appears as `"BASE"`, OP ETH as `"OP"`, not as `"ETH"`), so the
    /// reverse map is many-to-one only for legacy aliases (e.g. `"POL"` and
    /// `"MATIC"` both reaching `.polygon`).
    static func chain(forSwapKitChain swapKitChain: String) -> Chain? {
        switch swapKitChain.uppercased() {
        case "ETH": return .ethereum
        case "BSC", "BNB": return .bscChain
        case "AVAX": return .avalanche
        case "ARB": return .arbitrum
        case "OP": return .optimism
        case "BASE": return .base
        case "POL", "MATIC", "POLYGON": return .polygon
        case "SOL": return .solana
        case "BTC": return .bitcoin
        case "BCH": return .bitcoinCash
        case "LTC": return .litecoin
        case "DOGE": return .dogecoin
        case "DASH": return .dash
        case "ZEC": return .zcash
        case "TRON", "TRX": return .tron
        case "TON": return .ton
        case "ADA": return .cardano
        case "SUI": return .sui
        case "XRP": return .ripple
        case "ATOM": return .gaiaChain
        case "KUJI": return .kujira
        // Chains SwapKit lists tokens on but Vultisig doesn't hold wallets
        // for — caller drops the token. Enumerated for grep-discoverability
        // rather than relying on the default arm.
        case "BERA", "MONAD", "GNO", "STRK", "XLAYER", "OKB", "DOT", "NEAR":
            return nil
        default:
            return nil
        }
    }
}
