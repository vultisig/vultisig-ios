//
//  FunctionCallStakeTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallStakeTests: XCTestCase {

    func testInitDefaults() {
        let model = FunctionCallStake()
        XCTAssertEqual(model.amount, 0)
        XCTAssertEqual(model.nodeAddress, "")
        XCTAssertNil(model.customErrorMessage)
    }

    func testInitWithInitialAmountSeedsField() {
        let model = FunctionCallStake(initialAmount: 5)
        XCTAssertEqual(model.amount, 5)
    }

    /// Pin: legacy `toString()` returned the literal "d".
    func testToStringMatchesLegacyMemo() {
        let model = FunctionCallStake()
        XCTAssertEqual(model.toString(), "d")
    }

    func testToDictionaryMatchesLegacyKeys() {
        let model = FunctionCallStake()
        model.nodeAddress = "ton-validator"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["nodeAddress"], "ton-validator")
        XCTAssertEqual(dict["memo"], "d")
    }

    func testHandleAddressResultWritesNodeAddress() {
        let model = FunctionCallStake()
        model.handle(addressResult: AddressResult(address: "ton-stake-target"))
        XCTAssertEqual(model.nodeAddress, "ton-stake-target")
    }

    /// Pin: legacy validation flagged insufficient balance when amount
    /// exceeded `coin.balanceDecimal`.
    func testValidateSurfacesInsufficientBalance() {
        let model = FunctionCallStake(initialAmount: 10_000_000)
        let coin = FunctionCallFixture.makeTON(rawBalance: "1000")
        model.validate(against: coin)
        XCTAssertNotNil(model.customErrorMessage)
    }

    func testToSendTransactionWritesNodeAddressToToAddress() {
        let model = FunctionCallStake(initialAmount: 1)
        model.nodeAddress = "ton-stake"
        let coin = FunctionCallFixture.makeTON()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let tx = model.toSendTransaction(coin: coin, vault: vault, gas: 25, isFastVault: false)
        XCTAssertEqual(tx.memo, "d")
        XCTAssertEqual(tx.toAddress, "ton-stake")
    }
}
