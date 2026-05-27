//
//  FunctionCallBondMayaChainTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallBondMayaChainTests: XCTestCase {

    func testInitDefaults() {
        let model = FunctionCallBondMayaChain(assets: [])
        XCTAssertEqual(model.amount, 1)
        XCTAssertEqual(model.nodeAddress, "")
        XCTAssertEqual(model.fee, 0)
    }

    /// Pin: legacy `toString()` returned
    /// `BOND:<asset>:<fee>:<nodeAddress>`.
    func testToStringMatchesLegacyMemo() {
        let model = FunctionCallBondMayaChain(assets: [])
        model.selectedAsset = IdentifiableString(value: "BTC.BTC")
        model.fee = 5_000
        model.nodeAddress = "maya1bondnode"
        XCTAssertEqual(model.toString(), "BOND:BTC.BTC:5000:maya1bondnode")
    }

    func testToDictionaryMatchesLegacyKeys() {
        let model = FunctionCallBondMayaChain(assets: [])
        model.selectedAsset = IdentifiableString(value: "ETH.ETH")
        model.fee = 100
        model.nodeAddress = "maya1node"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["asset"], "ETH.ETH")
        XCTAssertEqual(dict["LPUNITS"], "100")
        XCTAssertEqual(dict["nodeAddress"], "maya1node")
        XCTAssertEqual(dict["memo"], "BOND:ETH.ETH:100:maya1node")
    }

    func testHandleAddressResultWritesNodeAddress() {
        let model = FunctionCallBondMayaChain(assets: [])
        model.handle(addressResult: AddressResult(address: "maya1bondtest"))
        XCTAssertEqual(model.nodeAddress, "maya1bondtest")
    }
}
