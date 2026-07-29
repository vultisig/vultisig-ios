//
//  OneInchCatalogRankingTests.swift
//  VultisigAppTests
//
//  Pins the 1inch whitelist's best-tier-first ordering. `CatalogToken` carries no
//  rank field, so the order the provider returns IS the quality signal — a
//  consumer that shows only the head of the list depends on it.
//
//  This is a quality TIER, not a ranking: `/swap/v6.0/{chain}/tokens` exposes no
//  volume, market-cap or liquidity field, so 1inch's own tag curation is all
//  there is to sort by.
//

import XCTest
@testable import VultisigApp

final class OneInchCatalogRankingTests: XCTestCase {

    private func token(_ symbol: String, tags: [String]?) -> OneInchToken {
        OneInchToken(address: "0x\(symbol)", symbol: symbol, name: symbol,
                     decimals: 18, logoURI: nil, providers: nil, tags: tags)
    }

    func testTiersOrderBluechipThenPeggedThenConnectorThenRest() {
        let unclassified = token("RANDOM", tags: ["tokens", "RWA"])
        let connector = token("CONN", tags: ["connector", "crosschain"])
        let pegged = token("DAI", tags: ["PEG:USD", "stablecoin"])
        let bluechip = token("WBTC", tags: ["bluechip", "connector", "PEG:BTC"])

        let ranked = OneInchToken.rankedForCatalog([unclassified, connector, pegged, bluechip])

        XCTAssertEqual(ranked.map { $0.symbol }, ["WBTC", "DAI", "CONN", "RANDOM"])
    }

    func testBluechipWinsWhenATokenCarriesSeveralTierTags() {
        // Most bluechips are also connectors and often pegged; the strongest tag
        // must decide the tier rather than whichever is checked first by accident.
        XCTAssertEqual(token("WETH", tags: ["connector", "PEG:ETH", "bluechip"]).catalogQualityTier, .bluechip)
        XCTAssertEqual(token("USDC", tags: ["connector", "PEG:USD"]).catalogQualityTier, .pegged)
        XCTAssertEqual(token("LINK", tags: ["connector", "defi"]).catalogQualityTier, .connector)
    }

    func testAnyPegPrefixCountsNotJustUSD() {
        XCTAssertEqual(token("stETH", tags: ["PEG:ETH"]).catalogQualityTier, .pegged)
        XCTAssertEqual(token("EURS", tags: ["PEG:EUR"]).catalogQualityTier, .pegged)
        XCTAssertEqual(token("tBTC", tags: ["PEG:BTC"]).catalogQualityTier, .pegged)
    }

    func testUntaggedTokenIsUnclassifiedNotACrash() {
        XCTAssertEqual(token("NOTAGS", tags: nil).catalogQualityTier, .unclassified)
        XCTAssertEqual(token("EMPTY", tags: []).catalogQualityTier, .unclassified)
    }

    func testTiesKeepTheCallersOrder() {
        // The provider hands the list in name order; within a tier 1inch tells us
        // nothing, so that order must survive rather than being reshuffled.
        let a = token("AAA", tags: ["bluechip"])
        let b = token("BBB", tags: ["bluechip"])
        let c = token("CCC", tags: ["bluechip"])

        XCTAssertEqual(OneInchToken.rankedForCatalog([a, b, c]).map { $0.symbol }, ["AAA", "BBB", "CCC"])
    }

    func testRankingIsIndependentOfTheRiskDowngrade() {
        // Tier and trust are orthogonal signals: a RISK-flagged bluechip still
        // ranks high, and is still withheld from browse by `.unverified`.
        let risky = token("SUS", tags: ["bluechip", "RISK:suspicious"])
        let clean = token("PLAIN", tags: ["tokens"])

        let ranked = OneInchToken.rankedForCatalog([clean, risky])

        XCTAssertEqual(ranked.map { $0.symbol }, ["SUS", "PLAIN"])
        XCTAssertEqual(risky.toCatalogToken(chain: .ethereum, sourceKind: "oneinch").verification, .unverified)
    }
}
