//
//  FunctionCallCosmosUnmergeTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallCosmosUnmergeTests: XCTestCase {

    /// Pin: legacy `toString()` returned
    /// `unmerge:<selectedToken.lowercased()>:<rawShares>` where
    /// `rawShares` is `amount * 1e8` formatted as an integer string
    /// without decimals.
    func testToStringMatchesLegacyShareEncoding() {
        let coin = FunctionCallFixture.makeRUJI()
        let vault = FunctionCallFixture.makeVault(coins: [FunctionCallFixture.makeRUNE(), coin])
        let model = FunctionCallCosmosUnmerge(coin: coin, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.RUJI")
        model.amount = 1.5 // 1.5 * 1e8 = 150_000_000
        XCTAssertEqual(model.toString(), "unmerge:thor.ruji:150000000")
    }

    func testToStringRoundsDownToInteger() {
        let coin = FunctionCallFixture.makeRUJI()
        let vault = FunctionCallFixture.makeVault(coins: [FunctionCallFixture.makeRUNE(), coin])
        let model = FunctionCallCosmosUnmerge(coin: coin, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.RUJI")
        model.amount = 0.00000001 // 1 raw share
        XCTAssertEqual(model.toString(), "unmerge:thor.ruji:1")
    }

    func testToDictionaryIncludesAllKeys() {
        let coin = FunctionCallFixture.makeRUJI()
        let vault = FunctionCallFixture.makeVault(coins: [FunctionCallFixture.makeRUNE(), coin])
        let model = FunctionCallCosmosUnmerge(coin: coin, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.RUJI")
        model.destinationAddress = "thor1mergecontract"
        model.amount = 1
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["destinationAddress"], "thor1mergecontract")
        XCTAssertEqual(dict["selectedToken"], "THOR.RUJI")
        XCTAssertEqual(dict["memo"], "unmerge:thor.ruji:100000000")
    }

    func testToSendTransactionTypeIsThorUnmerge() {
        let coin = FunctionCallFixture.makeRUJI()
        let vault = FunctionCallFixture.makeVault(coins: [FunctionCallFixture.makeRUNE(), coin])
        let model = FunctionCallCosmosUnmerge(coin: coin, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.RUJI")
        model.destinationAddress = "thor1mergecontract"
        model.amount = 1
        let tx = model.toSendTransaction(coin: coin, vault: vault, gas: 0, isFastVault: false)
        XCTAssertEqual(tx.transactionType, .thorUnmerge)
    }
}
