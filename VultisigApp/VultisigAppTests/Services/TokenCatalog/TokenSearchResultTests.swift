//
//  TokenSearchResultTests.swift
//  VultisigAppTests
//
//  Pins the wallet add-token picker's verification-aware split of the catalog
//  (`TokenSearchService.searchResult`): the auto-surfacing list stays curated /
//  verified only, the withheld `unverified` list carries the search-reveal
//  candidates minus spam, and the verification map lets the row views badge them.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TokenSearchResultTests: XCTestCase {

    private func meta(_ ticker: String, contract: String, logo: String = "logo", native: Bool = false) -> CoinMeta {
        CoinMeta(chain: .ethereum, ticker: ticker, logo: logo, decimals: 18,
                 priceProviderId: "", contractAddress: contract, isNativeToken: native)
    }

    private func token(_ ticker: String, _ verification: TokenVerification, contract: String, logo: String = "logo", native: Bool = false) -> CatalogToken {
        CatalogToken(meta: meta(ticker, contract: contract, logo: logo, native: native),
                     verification: verification, sourceKind: "test")
    }

    func testSurfaceableKeepsOnlyCuratedAndVerifiedNonNative() {
        let result = TokenSearchService.searchResult(from: [
            token("CUR", .curated, contract: "0x1"),
            token("VER", .verified(source: "CoinGecko"), contract: "0x2"),
            token("UNV", .unverified, contract: "0x3"),
            token("NATIVE", .verified(source: "CoinGecko"), contract: "", native: true)
        ])

        XCTAssertEqual(Set(result.surfaceable.map { $0.ticker }), ["CUR", "VER"])
    }

    func testUnverifiedListRevealsUnverifiedNonSpam() {
        let result = TokenSearchService.searchResult(from: [
            token("CUR", .curated, contract: "0x1"),
            token("PEPE", .unverified, contract: "0x2")
        ])

        XCTAssertEqual(result.unverified.map { $0.ticker }, ["PEPE"])
        XCTAssertFalse(result.surfaceable.contains { $0.ticker == "PEPE" },
                       "Unverified stays out of the auto-surfacing list")
    }

    func testUnverifiedListHardFiltersSpam() {
        let result = TokenSearchService.searchResult(from: [
            token("visit-x.com", .unverified, contract: "0x1"),   // URL-like ticker
            token("EMPTY", .unverified, contract: "0x2", logo: ""), // empty logo
            token("GOOD", .unverified, contract: "0x3")
        ])

        XCTAssertEqual(result.unverified.map { $0.ticker }, ["GOOD"],
                       "isLikelySpam is a hard gate on the unverified list")
    }

    func testSpamIsHardGatedFromSurfaceableToo() {
        // A verified (auto-surfacing) candidate with a spammy ticker must NOT
        // surface — spam is a hard gate on both lists, not just the withheld one.
        let result = TokenSearchService.searchResult(from: [
            token("visit.io", .verified(source: "CoinGecko"), contract: "0x1"),
            token("USDC", .verified(source: "CoinGecko"), contract: "0x2")
        ])

        XCTAssertEqual(result.surfaceable.map { $0.ticker }, ["USDC"],
                       "A verified token with a spammy ticker is still filtered")
        XCTAssertNil(result.verificationByUniqueId[meta("visit.io", contract: "0x1").uniqueId],
                     "Spam is dropped before the verification map is built")
    }

    func testUnverifiedNativeTokenIsDropped() {
        let result = TokenSearchService.searchResult(from: [
            token("NATIVE", .unverified, contract: "", native: true),
            token("GOOD", .unverified, contract: "0x1")
        ])

        XCTAssertEqual(result.unverified.map { $0.ticker }, ["GOOD"])
    }

    func testVerificationMapCarriesEachNonNativeTokensVerification() {
        let result = TokenSearchService.searchResult(from: [
            token("CUR", .curated, contract: "0x1"),
            token("VER", .verified(source: "Jupiter"), contract: "0x2"),
            token("UNV", .unverified, contract: "0x3")
        ])

        let cur = meta("CUR", contract: "0x1")
        let ver = meta("VER", contract: "0x2")
        let unv = meta("UNV", contract: "0x3")
        XCTAssertEqual(result.verificationByUniqueId[cur.uniqueId], .curated)
        XCTAssertEqual(result.verificationByUniqueId[ver.uniqueId], .verified(source: "Jupiter"))
        XCTAssertEqual(result.verificationByUniqueId[unv.uniqueId], .unverified)
    }
}
