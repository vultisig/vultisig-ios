//
//  SecuredAssetCatalogTests.swift
//  VultisigAppTests
//
//  Covers the secured-asset discovery catalog (denom → CoinMeta mapping,
//  load-bearing lowercasing, and the static fallback when the live
//  `/securedassets` fetch fails).
//

import XCTest
@testable import VultisigApp

@MainActor
final class SecuredAssetCatalogTests: XCTestCase {

    private enum StubError: Error { case unavailable }

    // MARK: - Mapper

    func testMapperEthUsdcTickerDecimalsAndContract() {
        let meta = SecuredAssetMapper.coinMeta(
            forDenom: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        )
        XCTAssertEqual(meta.chain, .thorChain)
        XCTAssertEqual(meta.ticker, "USDC")
        XCTAssertEqual(meta.decimals, 8)
        XCTAssertFalse(meta.isNativeToken)
        XCTAssertEqual(meta.contractAddress, "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        // Enriched from the curated TokensStore USDC entry (the feed has no logo).
        XCTAssertFalse(meta.logo.isEmpty)
    }

    func testMapperNativeBtcSecuredForm() {
        let meta = SecuredAssetMapper.coinMeta(forDenom: "btc-btc")
        XCTAssertEqual(meta.chain, .thorChain)
        XCTAssertEqual(meta.ticker, "BTC")
        XCTAssertEqual(meta.decimals, 8)
        XCTAssertFalse(meta.isNativeToken)
        XCTAssertEqual(meta.contractAddress, "btc-btc")
    }

    /// The catalog lowercases the uppercase `/securedassets` form; the resulting
    /// `uniqueId` must match a coin whose denom was persisted lowercase, or a
    /// held secured coin double-lists against its catalog twin.
    func testMapperUniqueIdCaseInsensitiveMatch() {
        let fromFeed = SecuredAssetMapper.coinMeta(
            forDenom: "ETH-USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48".lowercased()
        )
        let held = SecuredAssetMapper.coinMeta(
            forDenom: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        )
        XCTAssertEqual(fromFeed.uniqueId, held.uniqueId)
    }

    func testMapDedupesByUniqueId() {
        let metas = SecuredAssetCatalog.map(denoms: ["btc-btc", "btc-btc", "eth-eth"])
        XCTAssertEqual(metas.count, 2)
        XCTAssertEqual(metas.map { $0.ticker }, ["BTC", "ETH"])
    }

    // MARK: - Catalog

    func testCatalogMapsLiveFeedLowercased() async {
        let catalog = SecuredAssetCatalog(fetch: {
            [
                ThorchainSecuredAsset(
                    asset: "ETH-USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                    supply: "1",
                    depth: "1"
                ),
                ThorchainSecuredAsset(asset: "BTC-BTC", supply: "1", depth: "1")
            ]
        })
        let metas = await catalog.coinMetas()
        XCTAssertEqual(metas.count, 2)
        XCTAssertTrue(metas.allSatisfy { $0.chain == .thorChain && !$0.isNativeToken })
        XCTAssertEqual(metas.map { $0.ticker }, ["USDC", "BTC"])
        XCTAssertEqual(
            metas.first?.contractAddress,
            "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            "Live feed denoms must be lowercased to match held secured coins"
        )
    }

    func testCatalogFallsBackWhenFetchFails() async {
        let catalog = SecuredAssetCatalog(fetch: { throw StubError.unavailable })
        let metas = await catalog.coinMetas()
        XCTAssertEqual(metas.count, SecuredAssetCatalog.fallbackDenoms.count)
        XCTAssertTrue(metas.contains { $0.contractAddress == "btc-btc" })
        XCTAssertTrue(metas.allSatisfy { $0.chain == .thorChain && !$0.isNativeToken })
    }

    func testCatalogFallsBackWhenFeedEmpty() async {
        let catalog = SecuredAssetCatalog(fetch: { [] })
        let metas = await catalog.coinMetas()
        XCTAssertEqual(metas.count, SecuredAssetCatalog.fallbackDenoms.count)
    }
}
