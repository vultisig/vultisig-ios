//
//  FunctionCallReBondTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallReBondTests: XCTestCase {

    func testInitDefaults() {
        let model = FunctionCallReBond()
        XCTAssertEqual(model.rebondAmount, 0)
        XCTAssertEqual(model.nodeAddress, "")
        XCTAssertEqual(model.newAddress, "")
        XCTAssertEqual(model.amount, .zero)
    }

    /// Pin: legacy `toString()` returned
    /// `REBOND:<nodeAddress>:<newAddress>` and appended
    /// `:<amountInSmallestUnit>` only when `rebondAmount > 0`.
    func testToStringWithoutRebondAmountMatchesLegacy() {
        let model = FunctionCallReBond()
        model.nodeAddress = "thor1node"
        model.newAddress = "thor1new"
        XCTAssertEqual(model.toString(), "REBOND:thor1node:thor1new")
    }

    func testToStringWithRebondAmountAppendsRawSegment() {
        let model = FunctionCallReBond()
        model.nodeAddress = "thor1node"
        model.newAddress = "thor1new"
        model.rebondAmount = 100 // * 1e8 = 10_000_000_000
        XCTAssertEqual(model.toString(), "REBOND:thor1node:thor1new:10000000000")
    }

    func testToDictionaryOmitsRebondAmountWhenZero() {
        let model = FunctionCallReBond()
        model.nodeAddress = "thor1node"
        model.newAddress = "thor1new"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["nodeAddress"], "thor1node")
        XCTAssertEqual(dict["newAddress"], "thor1new")
        XCTAssertNil(dict["rebondAmount"])
    }

    func testToDictionaryIncludesRebondAmountWhenPositive() {
        let model = FunctionCallReBond()
        model.nodeAddress = "thor1node"
        model.newAddress = "thor1new"
        model.rebondAmount = 5
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["rebondAmount"], "5")
    }

    func testHandleNodeAddressResultWritesField() {
        let model = FunctionCallReBond()
        model.handle(nodeAddressResult: AddressResult(address: "thor1pasted-node"))
        XCTAssertEqual(model.nodeAddress, "thor1pasted-node")
    }

    func testHandleNewAddressResultWritesField() {
        let model = FunctionCallReBond()
        model.handle(newAddressResult: AddressResult(address: "thor1pasted-new"))
        XCTAssertEqual(model.newAddress, "thor1pasted-new")
    }

    /// Pin: REBOND's amount on the transaction MUST be zero — only the
    /// memo encodes the rebond amount.
    func testAmountIsAlwaysZero() {
        let model = FunctionCallReBond()
        model.rebondAmount = 1_000
        XCTAssertEqual(model.amount, .zero)
    }

    func testValidateSurfacesRebondRequiresRuneWhenWrongCoin() {
        let model = FunctionCallReBond()
        let nonRune = FunctionCallFixture.makeBTC()
        model.validate(against: nonRune)
        XCTAssertNotNil(model.customErrorMessage)
    }
}
