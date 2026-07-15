//
//  SecuredAssetCatalog.swift
//  VultisigApp
//
//  Dynamic catalog of THORChain secured assets for the swap destination
//  picker. Fetches the canonical universe from `/thorchain/securedassets`
//  (via `ThorchainService.fetchSecuredAssets`) and maps each dash-notation
//  denom to a `CoinMeta` on `.thorChain`, falling back to a small static list
//  when the live fetch fails so discovery still works offline.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "secured-asset-catalog")

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

    private let fetch: Fetcher

    init(fetch: @escaping Fetcher = { try await ThorchainService.shared.fetchSecuredAssets() }) {
        self.fetch = fetch
    }

    /// The live secured-asset universe mapped to `.thorChain` `CoinMeta`s,
    /// deduped by `uniqueId`. Falls back to the static list when the fetch
    /// fails or returns nothing, so the picker is never empty of secured
    /// assets while online-first data warms.
    func coinMetas() async -> [CoinMeta] {
        do {
            let assets = try await fetch()
            let metas = Self.map(denoms: assets.map { $0.asset.lowercased() })
            return metas.isEmpty ? Self.fallbackCoinMetas : metas
        } catch {
            logger.warning("secured asset catalog fetch failed: \(error.localizedDescription, privacy: .public)")
            return Self.fallbackCoinMetas
        }
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
    /// live `/securedassets` fetch fails. Intentionally small — the live list
    /// is ~2.5x larger, which is why the dynamic fetch is primary.
    static let fallbackDenoms: [String] = [
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
