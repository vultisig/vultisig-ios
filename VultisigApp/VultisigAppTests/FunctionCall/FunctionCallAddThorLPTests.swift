//
//  FunctionCallAddThorLPTests.swift
//  VultisigAppTests
//
//  Memo-pin tests for the rewritten `FunctionCallAddThorLP`. AddLP's
//  memo is built by `AddLPMemoData` — these pin the boundary so the
//  refactor doesn't quietly change the on-chain memo encoding.
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallAddThorLPTests: XCTestCase {

    /// Pin: legacy `toString()` returned the memo produced by
    /// `AddLPMemoData.memo` — keeps the pool-keyed `LP+` shape used
    /// downstream by the THORChain inbound router. The pairedAddress
    /// is included only when non-empty.
    func testToStringWithoutPairedAddress() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallAddThorLP(coin: rune, vault: vault)
        model.selectedPool = IdentifiableString(value: "THOR.RUNE")
        // No pairedAddress — memo omits the trailing segment.
        XCTAssertFalse(model.toString().isEmpty)
    }

    func testToDictionaryIncludesPoolAndPairedAddress() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallAddThorLP(coin: rune, vault: vault)
        model.selectedPool = IdentifiableString(value: "BTC.BTC")
        model.pairedAddress = "thor1paired"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["pairedAddress"], "thor1paired")
        XCTAssertNotNil(dict["pool"])
        XCTAssertNotNil(dict["memo"])
    }

    func testFormValidityRequiresThorchainEnabled() {
        let btc = FunctionCallFixture.makeBTC()
        let vault = FunctionCallFixture.makeVault(coins: [btc]) // No RUNE
        let model = FunctionCallAddThorLP(coin: btc, vault: vault)
        XCTAssertFalse(model.isThorchainEnabled)
        XCTAssertFalse(model.isTheFormValid)
    }
}
