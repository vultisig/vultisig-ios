//
//  FunctionCallCosmosMergeTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallCosmosMergeTests: XCTestCase {

    /// Pin: legacy `toString()` returned `merge:<selectedToken.value>`.
    func testToStringMatchesLegacyMemo() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallCosmosMerge(coin: rune, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.KUJI")
        XCTAssertEqual(model.toString(), "merge:THOR.KUJI")
    }

    func testToDictionaryIncludesDestinationAndMemo() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallCosmosMerge(coin: rune, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.KUJI")
        model.destinationAddress = "thor1mergeaddress"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["destinationAddress"], "thor1mergeaddress")
        XCTAssertEqual(dict["memo"], "merge:THOR.KUJI")
    }

    func testToSendTransactionTypeIsThorMerge() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallCosmosMerge(coin: rune, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.KUJI")
        model.destinationAddress = "thor1mergeaddress"
        let tx = model.toSendTransaction(coin: rune, vault: vault, gas: 0, isFastVault: false)
        XCTAssertEqual(tx.transactionType, .thorMerge)
        XCTAssertEqual(tx.toAddress, "thor1mergeaddress")
        XCTAssertEqual(tx.memo, "merge:THOR.KUJI")
    }

    func testAmountStartsAtZeroForNativeCoin() {
        let rune = FunctionCallFixture.makeRUNE() // native
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallCosmosMerge(coin: rune, vault: vault)
        // For native source, amount initializes to 0.0 per legacy.
        XCTAssertEqual(model.amount, 0.0)
    }

    /// Pin: amount > coin.balanceDecimal must fail the submit-time gate.
    /// Closes the latent over-balance hole — the no-arg `var
    /// isTheFormValid` only checked `isTokenSelected && amount > 0`.
    func testFormValidityRejectsAmountOverBalance() {
        let rune = FunctionCallFixture.makeRUNE(rawBalance: "1000000000")
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallCosmosMerge(coin: rune, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.RUJI")
        model.amount = rune.balanceDecimal + 1
        XCTAssertFalse(model.isFormValid(for: rune))
    }
}
