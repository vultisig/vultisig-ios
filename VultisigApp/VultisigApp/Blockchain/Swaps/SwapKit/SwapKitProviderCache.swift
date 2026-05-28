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

    private let httpClient: HTTPClientProtocol
    private var snapshot: SwapKitProvidersSnapshot?

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Returns a cached or freshly-fetched provider list, refreshing when the
    /// snapshot is older than `SwapKitConfig.providerCacheTTL`. Returns `nil`
    /// when the fetch fails *and* we have no prior snapshot — callers should
    /// treat that as "skip the SwapKit gate" rather than blocking the swap
    /// flow.
    func providers(now: Date = Date()) async -> [SwapKitProvider]? {
        if let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < SwapKitConfig.providerCacheTTL {
            return snapshot.providers
        }
        do {
            let response = try await httpClient.request(
                SwapKitAPI.providers,
                responseType: [SwapKitProvider].self
            )
            let fresh = SwapKitProvidersSnapshot(providers: response.data, fetchedAt: now)
            snapshot = fresh
            return fresh.providers
        } catch {
            return snapshot?.providers
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
    /// at least one non-filtered provider enabled. Returns `true` when the
    /// providers list can't be loaded (fail-open: better to attempt the
    /// fetcher and let `/v3/quote` decide than to silently disable SwapKit).
    func isEnabled(chain: Chain, now: Date = Date()) async -> Bool {
        guard let providers = await providers(now: now) else { return true }
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
    /// (fail-open, mirroring `isEnabled(chain:)`) — the caller treats this
    /// as "could plausibly be supported" when re-classifying error codes.
    func isPairSupported(fromChain: Chain, toChain: Chain, now: Date = Date()) async -> Bool {
        guard let providers = await providers(now: now) else { return true }
        return Self.pairEnabled(fromChain: fromChain, toChain: toChain, in: providers)
    }

    /// Replace the snapshot — exposed for tests so they don't have to stand
    /// up a fake HTTPClient.
    func setSnapshot(_ snapshot: SwapKitProvidersSnapshot) {
        self.snapshot = snapshot
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
