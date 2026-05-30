//
//  FunctionCallSecuredAssetTests.swift
//  VultisigAppTests
//
//  Memo-pin tests for the rewritten `FunctionCallSecuredAsset`
//  (SECURE+ mint).
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallSecuredAssetTests: XCTestCase {

    /// Pin: legacy `toString()` returned `SECURE+:<thorAddress>`.
    func testToStringMatchesLegacyMemo() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallSecuredAsset(coin: rune, vault: vault)
        model.thorAddress = "thor1secureplus"
        XCTAssertEqual(model.toString(), "SECURE+:thor1secureplus")
    }

    func testToDictionaryIncludesOperationAmountAndThorAddress() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallSecuredAsset(coin: rune, vault: vault)
        model.thorAddress = "thor1secureplus"
        model.amount = 100
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["operation"], "mint")
        XCTAssertEqual(dict["thorAddress"], "thor1secureplus")
        XCTAssertEqual(dict["memo"], "SECURE+:thor1secureplus")
    }
}
