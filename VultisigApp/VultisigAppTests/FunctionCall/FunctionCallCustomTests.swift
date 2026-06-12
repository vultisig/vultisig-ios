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

    func testFormValidRequiresTokenAndMemo() {
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let model = FunctionCallCustom(coin: coin, vault: vault)
        // RUNE is pre-selected via preSelectToken.
        XCTAssertTrue(model.isTokenSelected)
        XCTAssertFalse(model.isFormValid(for: coin))
        model.custom = "memo"
        XCTAssertTrue(model.isFormValid(for: coin))
    }

    /// Pin: an amount above the coin balance must fail the submit-time
    /// gate. The no-arg `isTheFormValid` only checked token + memo and
    /// let an over-balance custom amount navigate past Continue.
    func testFormValidRejectsAmountOverBalance() {
        let coin = FunctionCallFixture.makeRUNE(rawBalance: "100000000") // 1 RUNE
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let model = FunctionCallCustom(coin: coin, vault: vault)
        model.custom = "memo"
        model.amount = coin.balanceDecimal + 1
        XCTAssertFalse(model.isFormValid(for: coin))
    }

    /// A zero amount (memo-only custom call) stays valid — the amount
    /// field is optional.
    func testFormValidAllowsZeroAmount() {
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let model = FunctionCallCustom(coin: coin, vault: vault)
        model.custom = "memo"
        model.amount = 0
        XCTAssertTrue(model.isFormValid(for: coin))
    }
}
