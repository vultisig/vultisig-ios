//
//  FunctionCallUnstakeTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallUnstakeTests: XCTestCase {

    func testInitDefaults() {
        let model = FunctionCallUnstake()
        XCTAssertEqual(model.amount, 1)
        XCTAssertEqual(model.nodeAddress, "")
    }

    /// Pin: legacy `toString()` always returned the literal "w".
    func testToStringMatchesLegacyMemo() {
        let model = FunctionCallUnstake()
        XCTAssertEqual(model.toString(), "w")
        XCTAssertEqual(model.description, "w")
    }

    func testToDictionaryMatchesLegacyKeys() {
        let model = FunctionCallUnstake()
        model.nodeAddress = "ton-validator-addr"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["nodeAddress"], "ton-validator-addr")
        XCTAssertEqual(dict["memo"], "w")
        XCTAssertEqual(dict.count, 2)
    }

    func testHandleAddressResultWritesNodeAddress() {
        let model = FunctionCallUnstake()
        model.handle(addressResult: AddressResult(address: "ton-test"))
        XCTAssertEqual(model.nodeAddress, "ton-test")
    }

    /// Pin: validity requires amount > 0, amount <= coin.balanceDecimal,
    /// and a multi-chain THOR/Maya/TON address. Each gate is asserted
    /// independently — real bech32 / TON validity is covered by
    /// `FunctionCallAddressValidationTests`, so we only assert the
    /// closed-gate cases here.
    func testFormValidityGatesOnAmountAndAddress() {
        let model = FunctionCallUnstake()
        let coin = FunctionCallFixture.makeTON()
        // Empty address, amount = 1 (default) -> invalid (address gate)
        XCTAssertFalse(model.isFormValid(for: coin))

        // Garbage address but amount above balance -> invalid (both gates)
        model.nodeAddress = "not-an-address"
        model.amount = coin.balanceDecimal + 1
        XCTAssertFalse(model.isFormValid(for: coin))

        // Garbage address + zero amount -> invalid
        model.amount = 0
        XCTAssertFalse(model.isFormValid(for: coin))

        // Garbage address + valid amount -> still invalid (address gate)
        model.amount = 1
        XCTAssertFalse(model.isFormValid(for: coin))
    }

    func testToSendTransactionThreadsAddressOntoToAddress() {
        let model = FunctionCallUnstake()
        model.nodeAddress = "ton-validator"
        model.amount = 1
        let coin = FunctionCallFixture.makeTON()
        let vault = FunctionCallFixture.makeVault(coins: [coin])

        let tx = model.toSendTransaction(coin: coin, vault: vault, gas: 50)

        XCTAssertEqual(tx.memo, "w")
        XCTAssertEqual(tx.toAddress, "ton-validator")
        XCTAssertEqual(tx.transactionType, .unspecified)
    }

    /// Pin: amount > coin.balanceDecimal must fail the submit-time gate.
    /// Closes the latent over-balance hole the no-arg `var isTheFormValid`
    /// left for user-edited amounts.
    func testFormValidityRejectsAmountOverBalance() {
        let model = FunctionCallUnstake()
        let coin = FunctionCallFixture.makeTON(rawBalance: "1000000000") // 1 TON
        model.nodeAddress = FunctionCallFixture.thorAddress
        model.amount = coin.balanceDecimal + 1
        XCTAssertFalse(model.isFormValid(for: coin))
    }
}
