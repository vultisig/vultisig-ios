//
//  FunctionCallLeaveTests.swift
//  VultisigAppTests
//
//  Memo-pin + form-validity + boundary tests for the rewritten
//  `FunctionCallLeave` sub-model. Golden fixtures capture the legacy
//  output verbatim — any divergence would silently produce wrong
//  on-chain LEAVE memos.
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallLeaveTests: XCTestCase {

    func testInitProducesEmptyForm() {
        let model = FunctionCallLeave()
        XCTAssertEqual(model.nodeAddress, "")
        XCTAssertNil(model.customErrorMessage)
        XCTAssertNil(model.addressError)
        XCTAssertFalse(model.isTheFormValid)
    }

    // MARK: - Memo pin (golden fixture)

    /// Pin: legacy `toString()` returned `LEAVE:<nodeAddress>`. Captured
    /// from `FunctionCallLeave.swift:68` before the rewrite.
    func testToStringMatchesLegacyMemo() {
        let model = FunctionCallLeave()
        model.nodeAddress = "thor1abc"
        XCTAssertEqual(model.toString(), "LEAVE:thor1abc")
        XCTAssertEqual(model.description, "LEAVE:thor1abc")
    }

    /// Pin: legacy `toDictionary()` returned a dict with
    /// `nodeAddress` + `memo` keys.
    func testToDictionaryMatchesLegacyKeys() {
        let model = FunctionCallLeave()
        model.nodeAddress = "thor1abc"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["nodeAddress"], "thor1abc")
        XCTAssertEqual(dict["memo"], "LEAVE:thor1abc")
        XCTAssertEqual(dict.count, 2)
    }

    // MARK: - Validity

    func testIsTheFormValidGatesOnAddress() {
        let model = FunctionCallLeave()
        XCTAssertFalse(model.isTheFormValid)
        model.nodeAddress = ""
        XCTAssertFalse(model.isTheFormValid)
        // Garbage address must keep the gate closed — `isValidThorMayaTON`
        // runs real bech32 / TON validation under the hood.
        model.nodeAddress = "not-an-address"
        XCTAssertFalse(model.isTheFormValid)
    }

    func testHandleAddressResultWritesNodeAddress() {
        let model = FunctionCallLeave()
        model.handle(addressResult: AddressResult(address: "thor1xyz"))
        XCTAssertEqual(model.nodeAddress, "thor1xyz")
    }

    func testHandleAddressResultIgnoresNil() {
        let model = FunctionCallLeave()
        model.nodeAddress = "thor1original"
        model.handle(addressResult: nil)
        XCTAssertEqual(model.nodeAddress, "thor1original")
    }

    // MARK: - Boundary (toSendTransaction)

    func testToSendTransactionMemoMatchesLegacy() {
        let model = FunctionCallLeave()
        model.nodeAddress = "thor1abc"
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])

        let tx = model.toSendTransaction(coin: coin, vault: vault, gas: 100, isFastVault: false)

        XCTAssertEqual(tx.memo, "LEAVE:thor1abc")
        XCTAssertEqual(tx.coin.ticker, "RUNE")
        XCTAssertEqual(tx.gas, 100)
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "LEAVE:thor1abc")
        XCTAssertEqual(tx.memoFunctionDictionary["nodeAddress"], "thor1abc")
    }

    func testToSendTransactionAmountIsZeroDecimalString() {
        let model = FunctionCallLeave()
        model.nodeAddress = "thor1abc"
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])

        let tx = model.toSendTransaction(coin: coin, vault: vault, gas: 0, isFastVault: false)

        XCTAssertEqual(model.amount, .zero)
        XCTAssertEqual(tx.amount, "0")
    }
}
