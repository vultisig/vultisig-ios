//
//  FunctionCallUnbondMayaChainTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallUnbondMayaChainTests: XCTestCase {

    func testInitWithPreloadedAssets() {
        let assets = [IdentifiableString(value: "BTC.BTC"), IdentifiableString(value: "ETH.ETH")]
        let model = FunctionCallUnbondMayaChain(assets: assets)
        XCTAssertEqual(model.assets.count, 2)
        XCTAssertEqual(model.assets.map { $0.value }, ["BTC.BTC", "ETH.ETH"])
    }

    /// Pin: legacy `toString()` returned
    /// `UNBOND:<asset>:<fee>:<nodeAddress>`.
    func testToStringMatchesLegacyMemo() {
        let model = FunctionCallUnbondMayaChain(assets: [])
        model.selectedAsset = IdentifiableString(value: "BTC.BTC")
        model.fee = 1234
        model.nodeAddress = "maya1abc"
        XCTAssertEqual(model.toString(), "UNBOND:BTC.BTC:1234:maya1abc")
    }

    func testToDictionaryMatchesLegacyKeys() {
        let model = FunctionCallUnbondMayaChain(assets: [])
        model.selectedAsset = IdentifiableString(value: "BTC.BTC")
        model.fee = 1234
        model.nodeAddress = "maya1abc"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["asset"], "BTC.BTC")
        XCTAssertEqual(dict["LPUNITS"], "1234")
        XCTAssertEqual(dict["nodeAddress"], "maya1abc")
        XCTAssertEqual(dict["memo"], "UNBOND:BTC.BTC:1234:maya1abc")
    }

    func testHandleAddressResultWritesNodeAddress() {
        let model = FunctionCallUnbondMayaChain(assets: [])
        model.handle(addressResult: AddressResult(address: "maya1test"))
        XCTAssertEqual(model.nodeAddress, "maya1test")
    }

    /// Pin: dust amount is `1 / pow(10, 8)`, matches
    /// `FunctionCallInstance.amount`'s `.unbondMaya` branch.
    func testAmountIsFixedDust() {
        let model = FunctionCallUnbondMayaChain(assets: [])
        XCTAssertEqual(model.amount, 1 / pow(Decimal(10), 8))
    }
}
