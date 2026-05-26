//
//  FunctionCallCustomTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallCustomTests: XCTestCase {

    func testInitLoadsThorchainTokensFromVault() {
        let rune = FunctionCallFixture.makeRUNE()
        let tcy = FunctionCallFixture.makeTCY()
        let vault = FunctionCallFixture.makeVault(coins: [rune, tcy])
        let model = FunctionCallCustom(coin: rune, vault: vault)
        XCTAssertTrue(model.tokens.map { $0.value }.contains("RUNE"))
        XCTAssertTrue(model.tokens.map { $0.value }.contains("TCY"))
    }

    func testInitFallsBackToRuneWhenVaultMissesTokens() {
        let onlyBTC = FunctionCallFixture.makeBTC()
        let rune = FunctionCallFixture.makeRUNE()
        // Construct vault holding BTC only; FunctionCallCustom is for
        // THOR/Maya — verifies fallback.
        let vault = FunctionCallFixture.makeVault(coins: [onlyBTC])
        let model = FunctionCallCustom(coin: rune, vault: vault)
        XCTAssertEqual(model.tokens.first?.value, "RUNE")
    }

    /// Pin: legacy `toString()` returned the free-form custom memo as-is.
    func testToStringMatchesLegacyMemo() {
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let model = FunctionCallCustom(coin: coin, vault: vault)
        model.custom = "arbitrary-memo-string"
        XCTAssertEqual(model.toString(), "arbitrary-memo-string")
    }

    func testToDictionaryMatchesLegacyKeys() {
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let model = FunctionCallCustom(coin: coin, vault: vault)
        model.custom = "hello"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["memo"], "hello")
        XCTAssertEqual(dict.count, 1)
    }

    func testIsTheFormValidRequiresTokenAndMemo() {
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let model = FunctionCallCustom(coin: coin, vault: vault)
        // RUNE is pre-selected via preSelectToken.
        XCTAssertTrue(model.isTokenSelected)
        XCTAssertFalse(model.isTheFormValid)
        model.custom = "memo"
        XCTAssertTrue(model.isTheFormValid)
    }
}
