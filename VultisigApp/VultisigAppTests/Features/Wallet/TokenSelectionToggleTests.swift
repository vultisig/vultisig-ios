//
//  TokenSelectionToggleTests.swift
//  VultisigAppTests
//
//  Pins the "Show unverified" toggle gating: the search pool only includes the
//  withheld unverified candidates when the opt-in is on, and search surfaces
//  them accordingly.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TokenSelectionToggleTests: XCTestCase {

    private func meta(_ ticker: String, _ contract: String) -> CoinMeta {
        CoinMeta(chain: .ethereum, ticker: ticker, logo: "logo", decimals: 18,
                 priceProviderId: "", contractAddress: contract, isNativeToken: false)
    }

    func testSearchPoolHidesUnverifiedWhenToggleOff() {
        let verified = [meta("USDC", "0x1")]
        let unverified = [meta("PEPE", "0x2")]

        let pool = TokenSelectionLogic.searchPool(verified: verified, unverified: unverified, showUnverified: false)

        XCTAssertEqual(pool.map { $0.ticker }, ["USDC"])
    }

    func testSearchPoolRevealsUnverifiedWhenToggleOn() {
        let verified = [meta("USDC", "0x1")]
        let unverified = [meta("PEPE", "0x2")]

        let pool = TokenSelectionLogic.searchPool(verified: verified, unverified: unverified, showUnverified: true)

        XCTAssertEqual(pool.map { $0.ticker }, ["USDC", "PEPE"])
    }

    func testSearchOnlyMatchesUnverifiedOncePoolIncludesThem() {
        let verified = [meta("USDC", "0x1")]
        let unverified = [meta("PEPE", "0x2")]
        let logic = TokenSelectionLogic.shared

        let poolOff = TokenSelectionLogic.searchPool(verified: verified, unverified: unverified, showUnverified: false)
        let hidden = logic.filteredTokens(chainCoins: [], searchText: "pepe", tokens: poolOff)
        XCTAssertTrue(hidden.isEmpty, "Unverified token isn't searchable while the toggle is off")

        let poolOn = TokenSelectionLogic.searchPool(verified: verified, unverified: unverified, showUnverified: true)
        let shown = logic.filteredTokens(chainCoins: [], searchText: "pepe", tokens: poolOn)
        XCTAssertEqual(shown.map { $0.ticker }, ["PEPE"], "Unverified token is searchable once revealed")
    }
}
