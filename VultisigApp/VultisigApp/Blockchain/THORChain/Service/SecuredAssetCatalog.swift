//
//  SecuredAssetCatalog.swift
//  VultisigApp
//
//  Dynamic catalog of THORChain secured assets for the swap destination
//  picker and the wallet add-token screen. Lists the `/thorchain/securedassets`
//  universe (via `ThorchainService.fetchSecuredAssets`) restricted to assets
//  whose THORChain pool is Available, and maps each dash-notation denom to a
//  `CoinMeta` on `.thorChain`. Falls back to a small static list when either
//  live fetch fails, so discovery still works offline instead of listing the
//  live feed unfiltered.
//

import Foundation
import OSLog

private let logger = Log.chain.other

/// One entry from THORNode `/thorchain/securedassets`. `asset` is the uppercase
/// dash-notation denom (e.g. `ETH-USDC-0X…`, `BTC-BTC`); `supply`/`depth` are
/// decoded defensively (optional) since only `asset` drives the catalog.
struct ThorchainSecuredAsset: Codable, Sendable, Equatable {
    let asset: String
    let supply: String?
    let depth: String?
}

/// Maps a THORChain secured-asset denom to a `CoinMeta`. Shared by the discovery
/// catalog and the SECURE+ withdraw picker so both derive identical metadata —
/// the `uniqueId` (chain + lowercased ticker + lowercased contract) must match
/// between a held secured coin and its catalog twin, or the picker double-lists.
enum SecuredAssetMapper {

    /// Builds a `CoinMeta` from a secured-asset denom.
    ///
    /// - `denom` is stored verbatim as `contractAddress`; callers sourcing the
    ///   uppercase `/securedassets` form must lowercase it first so it matches
    ///   held secured coins (persisted lowercase from bank balances).
    /// - `ticker`/`decimals` come from `THORChainTokenMetadataFactory` (splits on
    ///   `-`, decimals = 8) — the same derivation `fetchTokens` uses, so a held
    ///   secured coin and its catalog twin share a ticker (hence a `uniqueId`).
    /// - `logo`/`priceProviderId` are enriched from a `TokensStore` ticker match
    ///   when one exists (the feed carries neither).
    nonisolated static func coinMeta(forDenom denom: String, chain: Chain = .thorChain) -> CoinMeta {
        let info = THORChainTokenMetadataFactory.create(asset: denom)
        let ticker = info.ticker.uppercased()
        let localAsset = TokensStore.TokenSelectionAssets.first {
            $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame
        }
        return CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: localAsset?.logo ?? info.logo,
            decimals: info.decimals,
            priceProviderId: localAsset?.priceProviderId ?? "",
            contractAddress: denom,
            isNativeToken: false
        )
    }
}

@MainActor
final class SecuredAssetCatalog {

    typealias Fetcher = () async throws -> [ThorchainSecuredAsset]
    /// Asset names (`ETH.USDC-0X…`) of the THORChain pools whose status is Available.
    typealias AvailablePoolsFetcher = () async throws -> [String]

    private let fetch: Fetcher
    private let availablePools: AvailablePoolsFetcher

    init(
        fetch: @escaping Fetcher = { try await ThorchainService.shared.fetchSecuredAssets() },
        availablePools: @escaping AvailablePoolsFetcher = {
            try await ThorchainService.shared.fetchLPPools().filter(\.isAvailable).map(\.asset)
        }
    ) {
        self.fetch = fetch
        self.availablePools = availablePools
    }

    /// The live secured assets whose pool is Available, mapped to `.thorChain`
    /// `CoinMeta`s and deduped by `uniqueId`. Falls back to the static list when
    /// either fetch fails or nothing is left, so the picker is never empty of
    /// secured assets and never shows the unfiltered live list.
    func coinMetas() async -> [CoinMeta] {
        do {
            let assets = try await fetch()
            let pools = Set(try await availablePools().map { $0.uppercased() })
            let listed = assets.filter { pools.contains(Self.poolAsset(forDenom: $0.asset)) }
            let metas = Self.map(denoms: listed.map { $0.asset.lowercased() })
            return metas.isEmpty ? Self.fallbackCoinMetas : metas
        } catch {
            logger.warning("secured asset catalog fetch failed: \(error.localizedDescription, privacy: .public)")
            return Self.fallbackCoinMetas
        }
    }

    /// The pool asset a secured denom belongs to (`ETH-USDC-0X…` → `ETH.USDC-0X…`),
    /// uppercased for comparison.
    private nonisolated static func poolAsset(forDenom denom: String) -> String {
        denom.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .joined(separator: ".")
            .uppercased()
    }

    /// Maps denoms to `CoinMeta`, deduping by `uniqueId`, preserving order.
    /// Exposed for tests.
    nonisolated static func map(denoms: [String]) -> [CoinMeta] {
        var seen = Set<String>()
        var result: [CoinMeta] = []
        for denom in denoms {
            let meta = SecuredAssetMapper.coinMeta(forDenom: denom)
            guard !seen.contains(meta.uniqueId) else { continue }
            seen.insert(meta.uniqueId)
            result.append(meta)
        }
        return result
    }

    /// Canonical secured denoms (lowercase dash notation) used only when the
    /// live `/securedassets` or `/pools` fetch fails. Intentionally small — the
    /// live list is ~2x larger, which is why the dynamic fetch is primary.
    nonisolated static let fallbackDenoms: [String] = [
        "btc-btc",
        "eth-eth",
        "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "eth-usdt-0xdac17f958d2ee523a2206206994597c13d831ec7",
        "bsc-bnb",
        "base-eth",
        "base-usdc-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
        "gaia-atom",
        "avax-avax",
        "avax-usdc-0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e",
        "ltc-ltc",
        "bch-bch",
        "doge-doge",
        "sol-sol",
        "xrp-xrp"
    ]

    nonisolated static var fallbackCoinMetas: [CoinMeta] {
        map(denoms: fallbackDenoms)
    }
}
