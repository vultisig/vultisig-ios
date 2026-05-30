//
//  FunctionCallWithdrawSecuredAssetTests.swift
//  VultisigAppTests
//
//  Memo-pin tests for the rewritten `FunctionCallWithdrawSecuredAsset`
//  (SECURE+ withdraw).
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallWithdrawSecuredAssetTests: XCTestCase {

    /// Pin: legacy `toString()` returned `SECURE-:<destinationAddress>`.
    func testToStringMatchesLegacyMemo() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallWithdrawSecuredAsset(coin: rune, vault: vault)
        model.destinationAddress = "0xL1DestAddr"
        XCTAssertEqual(model.toString(), "SECURE-:0xL1DestAddr")
    }

    func testToDictionaryIncludesOperationAndDestination() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallWithdrawSecuredAsset(coin: rune, vault: vault)
        model.destinationAddress = "0xL1DestAddr"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["operation"], "withdraw")
        XCTAssertEqual(dict["destinationAddress"], "0xL1DestAddr")
        XCTAssertEqual(dict["memo"], "SECURE-:0xL1DestAddr")
    }

    func testInitialSelectedSecuredAssetIsPlaceholder() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallWithdrawSecuredAsset(coin: rune, vault: vault)
        XCTAssertEqual(model.selectedSecuredAsset.value, FunctionCallWithdrawSecuredAsset.initialItemForDropdownText)
    }
}
