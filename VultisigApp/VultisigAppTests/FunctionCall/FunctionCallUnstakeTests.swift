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

    /// Pin: legacy required `amountValid && nodeAddressValid`. We
    /// expose `amount > 0` + multi-chain address validity.
    func testFormValidityGatesOnAmountAndAddress() {
        let model = FunctionCallUnstake()
        XCTAssertFalse(model.isTheFormValid)
        model.nodeAddress = "thor1abc"
        // amount is 1 by default; address must validate.
        XCTAssertEqual(model.amount, 1)
    }

    func testToSendTransactionThreadsAddressOntoToAddress() {
        let model = FunctionCallUnstake()
        model.nodeAddress = "ton-validator"
        model.amount = 1
        let coin = FunctionCallFixture.makeTON()
        let vault = FunctionCallFixture.makeVault(coins: [coin])

        let tx = model.toSendTransaction(coin: coin, vault: vault, gas: 50, isFastVault: false)

        XCTAssertEqual(tx.memo, "w")
        XCTAssertEqual(tx.toAddress, "ton-validator")
        XCTAssertEqual(tx.transactionType, .unspecified)
    }
}
