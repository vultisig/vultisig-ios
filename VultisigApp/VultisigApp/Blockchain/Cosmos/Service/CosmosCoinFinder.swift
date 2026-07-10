//
//  CosmosCoinFinder.swift
//  VultisigApp
//
//  Auto-discovers Cosmos bank denoms held at a Terra / TerraClassic address
//  and resolves each into a `DiscoveredCosmosDenom` carrying ticker /
//  decimals / hidden-flag. Mirrors the SDK `findCosmosCoins` resolver in
//  `vultisig-sdk/packages/core/chain/coin/find/resolvers/cosmos.ts` — same
//  allowlist, same fallback chain, same hidden semantics.
//
//  Why an `actor`: concurrent callers (balance refresh fan-out, vault
//  switch) share a single resolver instance and its cache. Discovery work
//  itself is fan-out — `discoverBankDenoms` blasts through balances and
//  resolves metadata per denom in parallel via `withTaskGroup`.
//
//  Allowlist: `terra` and `terraClassic` only (matches the SDK's
//  `AUTO_DISCOVERY_CHAINS` set). Other Cosmos chains return `[]` without a
//  network call — they keep using the curated `TokensStore` path. THORChain
//  has its own resolver under `ThorchainService.fetchTokens` and is not
//  rerouted here.
//

import Foundation
import OSLog

actor CosmosCoinFinder {

    static let shared = CosmosCoinFinder()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "cosmos-discovery")
    private let httpClient: HTTPClientProtocol
    private let metadataResolver: CosmosTokenMetadataResolver

    /// Chains for which bank-denom auto-discovery is enabled. The SDK's
    /// `AUTO_DISCOVERY_CHAINS` matches this set. Adding a new chain here
    /// requires the same chain to land in `CosmosServiceConfig.baseURL`
    /// and in `chainFeeDecimals` below.
    static let allowlistedChains: Set<Chain> = [.terra, .terraClassic]

    /// Chains whose LCD nodes implement `GET /ibc/apps/transfer/v1/
    /// denom_traces/{hash}`. Terra Classic LCDs (publicnode, hexxagon,
    /// binodes) all return `code 12 Not Implemented` for this endpoint,
    /// so we skip the trace recursion there and fall through to the
    /// hidden tier — same end-state the SDK reaches because it doesn't
    /// implement IBC trace lookups for any chain.
    static let ibcTraceCapableChains: Set<Chain> = [.terra]

    /// Chains whose LCD nodes implement the modern ibc-go
    /// `GET /ibc/apps/transfer/v1/denoms/{hash}` endpoint. Terra Classic
    /// serves this (publicnode) even though it rejects the deprecated
    /// `denom_traces/{hash}` path with `code 12 Not Implemented`, so it's the
    /// resolution path we use to turn a held `ibc/<hash>` voucher into a real
    /// base denom there. Phoenix-1 (`.terra`) stays on its existing working
    /// `denom_traces` path to avoid regressing it.
    static let ibcModernDenomChains: Set<Chain> = [.terraClassic]

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        metadataResolver: CosmosTokenMetadataResolver = CosmosTokenMetadataResolver.shared
    ) {
        self.httpClient = httpClient
        self.metadataResolver = metadataResolver
    }

    // MARK: - Public surface

    /// Discover held bank denoms at the given address on the given chain.
    /// Returns `[]` for non-allowlisted chains WITHOUT making a network
    /// call. Throws when the balance fetch itself fails (per-denom
    /// metadata failures fall through to `isHidden = true` rather than
    /// failing the whole call).
    func discoverBankDenoms(chain: Chain, address: String) async throws -> [DiscoveredCosmosDenom] {
        guard Self.allowlistedChains.contains(chain) else {
            return []
        }

        let balances = try await fetchBalances(chain: chain, address: address)

        // Filter the native fee denom — it's already represented as the
        // chain's `isNativeToken` entry on the vault. Mirrors the SDK's
        // `without(..., cosmosFeeCoinDenom[chain])` filter.
        let feeDenom = Self.feeDenom(for: chain)
        let candidateDenoms = balances
            .map { $0.denom }
            .filter { $0 != feeDenom }

        // Resolve metadata in parallel. Each resolution is independent and
        // the metadata resolver coalesces concurrent in-flight requests for
        // the same denom, so the fan-out is bounded by the unique-denom
        // count, not the balance count.
        var resolved: [DiscoveredCosmosDenom] = []
        await withTaskGroup(of: DiscoveredCosmosDenom?.self) { group in
            for denom in candidateDenoms {
                group.addTask { [metadataResolver] in
                    await Self.resolve(
                        chain: chain,
                        denom: denom,
                        metadataResolver: metadataResolver
                    )
                }
            }
            for await result in group {
                if let result {
                    resolved.append(result)
                }
            }
        }

        return resolved
    }

    // MARK: - Per-denom resolution

    /// Run the SDK fallback chain for a single denom:
    /// 1. Direct metadata lookup (cached).
    /// 2. List-fetch fallback (same resolver call).
    /// 3. If still empty AND denom is `ibc/<HASH>`: trace it, recurse on
    ///    the base denom from the trace.
    /// 4. If still empty: derive ticker, mark `isHidden = true`, use the
    ///    chain's fee-coin decimals so formatting doesn't explode.
    ///
    /// Prefer a curated `TokensStore` entry when chain + denom match — that
    /// path gives bundled logos and a working `priceProviderId`. Mirrors
    /// `MayachainService.fetchTokens` / `ThorchainService.fetchTokens`.
    private static func resolve(
        chain: Chain,
        denom: String,
        metadataResolver: CosmosTokenMetadataResolver
    ) async -> DiscoveredCosmosDenom? {
        // Prefer the curated entry before hitting the LCD — saves a round
        // trip when we already ship a logo + priceProviderId for this denom.
        if let curated = TokensStore.findTokenMeta(chain: chain, contractAddress: denom) {
            return DiscoveredCosmosDenom(
                denom: denom,
                ticker: curated.ticker,
                decimals: curated.decimals,
                logo: curated.logo,
                priceProviderId: curated.priceProviderId,
                isHidden: false
            )
        }

        // Tier 1+2: direct denom_metadata, then list-fetch fallback. Both
        // are handled inside the resolver behind one cache key.
        let directMeta = await metadataResolver.denomMetadata(chain: chain, denom: denom)
        if let directMeta, let decimals = CosmosTokenMetadataResolver.decimalsFromMeta(directMeta) {
            let ticker = CosmosTokenMetadataResolver.deriveTicker(denom: denom, meta: directMeta)
            return makeDiscovered(
                chain: chain,
                denom: denom,
                ticker: ticker,
                decimals: decimals,
                isHidden: false
            )
        }

        // Tier 2b: modern IBC resolution. Terra Classic LCDs implement the
        // ibc-go `/denoms/{hash}` endpoint (but reject the deprecated
        // `denom_traces/{hash}` path used by Tier 3), so for an `ibc/<HASH>`
        // voucher on such a chain we resolve the base denom here, derive a
        // ticker from it (`uusdc` -> `USDC`), and take decimals from the base
        // denom's metadata when present, else the chain fee-coin fallback.
        // `isHidden = true` mirrors the SDK's semantics for a discovered IBC
        // voucher; `makeDiscovered` still backfills a curated logo /
        // priceProviderId when the derived ticker matches a bundled entry.
        if denom.hasPrefix("ibc/"), Self.ibcModernDenomChains.contains(chain) {
            if let baseDenom = await metadataResolver.ibcDenom(chain: chain, denom: denom) {
                let baseMeta = await metadataResolver.denomMetadata(chain: chain, denom: baseDenom)
                let decimals = baseMeta.flatMap(CosmosTokenMetadataResolver.decimalsFromMeta)
                    ?? feeDecimals(for: chain)
                let ticker = CosmosTokenMetadataResolver.ibcTicker(baseDenom: baseDenom)
                return makeDiscovered(
                    chain: chain,
                    denom: denom,
                    ticker: ticker,
                    decimals: decimals,
                    isHidden: true
                )
            }
            // Voucher unknown to the modern endpoint — fall through to the
            // hidden tier, which now yields `IBC-<6hex>` via deriveTicker.
        }

        // Tier 3: IBC trace recursion. Only applies to `ibc/<HASH>` denoms;
        // the resolver short-circuits non-IBC inputs without a network call.
        // Terra Classic LCDs return `code 12 Not Implemented` for the
        // denom_traces endpoint, so we skip the trace recursion there.
        // This matches the SDK, which has no IBC trace lookup logic at all
        // — it simply falls through to the throw / hidden path when direct
        // metadata is missing. Phoenix-1 LCDs implement the endpoint, so
        // we keep the recursion on `.terra` for richer ticker derivation.
        if denom.hasPrefix("ibc/"), Self.ibcTraceCapableChains.contains(chain) {
            if let trace = await metadataResolver.ibcDenomTrace(chain: chain, denom: denom) {
                let baseDenom = trace.baseDenom
                let baseMeta = await metadataResolver.denomMetadata(chain: chain, denom: baseDenom)
                if let baseMeta, let decimals = CosmosTokenMetadataResolver.decimalsFromMeta(baseMeta) {
                    let ticker = CosmosTokenMetadataResolver.deriveTicker(denom: baseDenom, meta: baseMeta)
                    // The trace yielded a base denom but the recursion is
                    // an opaque IBC asset — preserve `isHidden = true` per
                    // SDK semantics.
                    return makeDiscovered(
                        chain: chain,
                        denom: denom,
                        ticker: ticker,
                        decimals: decimals,
                        isHidden: true
                    )
                }
                // Trace returned but no base metadata — fall through to
                // the hidden-with-derived-ticker tier using the base denom
                // string for ticker derivation.
                let ticker = CosmosTokenMetadataResolver.deriveTicker(denom: baseDenom, meta: nil)
                return makeDiscovered(
                    chain: chain,
                    denom: denom,
                    ticker: ticker,
                    decimals: feeDecimals(for: chain),
                    isHidden: true
                )
            }
        }

        // Tier 4: hidden fallback. Derive a ticker from the denom string
        // and use the chain's fee-coin decimals so balance formatting
        // doesn't divide by zero. Mirrors the SDK's "not dropped, just
        // hidden" semantic for Terra/TerraClassic.
        let ticker = CosmosTokenMetadataResolver.deriveTicker(denom: denom, meta: nil)
        return makeDiscovered(
            chain: chain,
            denom: denom,
            ticker: ticker,
            decimals: feeDecimals(for: chain),
            isHidden: true
        )
    }

    private static func makeDiscovered(
        chain: Chain,
        denom: String,
        ticker: String,
        decimals: Int,
        isHidden: Bool
    ) -> DiscoveredCosmosDenom {
        // Even when metadata-lookup succeeds, prefer the curated
        // TokensStore entry's logo + priceProviderId if one exists for the
        // resolved ticker — the bundled asset is higher-fidelity than an
        // empty-string fallback. We match on ticker (case-insensitive)
        // rather than contract address because metadata-resolved denoms
        // may not share the curated entry's contract string.
        let curated = TokensStore.TokenSelectionAssets.first {
            $0.chain == chain && $0.ticker.uppercased() == ticker.uppercased()
        }
        let logo = curated?.logo ?? ""
        let priceProviderId = curated?.priceProviderId ?? ""
        return DiscoveredCosmosDenom(
            denom: denom,
            ticker: ticker,
            decimals: decimals,
            logo: logo,
            priceProviderId: priceProviderId,
            isHidden: isHidden
        )
    }

    // MARK: - Balance fetch

    private func fetchBalances(chain: Chain, address: String) async throws -> [CosmosBalance] {
        let config = try CosmosServiceConfig.getConfig(forChain: chain)
        guard let baseURL = config.baseURL else {
            return []
        }

        let endpoint: CosmosAPI.Endpoint = config.usesSpendableBalances
            ? .spendableBalance(address: address)
            : .balance(address: address)

        let response = try await httpClient.request(
            CosmosAPI(baseURL: baseURL, endpoint: endpoint),
            responseType: CosmosBalanceResponse.self
        )
        return response.data.balances
    }

    // MARK: - Chain table helpers

    /// Native fee denom per chain — the denom we filter out before
    /// metadata resolution because it's already the vault's native coin.
    /// Mirrors the SDK `cosmosFeeCoinDenom` table.
    static func feeDenom(for chain: Chain) -> String {
        switch chain {
        case .terra, .terraClassic:
            return "uluna"
        default:
            return ""
        }
    }

    /// Fallback decimals used by the hidden tier — when no metadata is
    /// available, the SDK uses `chainFeeCoin[chain].decimals`. Terra and
    /// TerraClassic both have 6-decimal native coins.
    static func feeDecimals(for chain: Chain) -> Int {
        switch chain {
        case .terra, .terraClassic:
            return 6
        default:
            return 6
        }
    }
}
