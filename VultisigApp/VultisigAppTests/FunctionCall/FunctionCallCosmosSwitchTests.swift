//
//  FunctionCallCosmosSwitchTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallCosmosSwitchTests: XCTestCase {

    func testInitPrefillsThorAddressFromVault() {
        let rune = FunctionCallFixture.makeRUNE()
        let atom = FunctionCallFixture.makeATOM()
        let vault = FunctionCallFixture.makeVault(coins: [rune, atom])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        XCTAssertEqual(model.thorAddress, rune.address)
    }

    func testInitSeedsAmountFromCoinBalance() {
        let atom = FunctionCallFixture.makeATOM(rawBalance: "1000000")
        let vault = FunctionCallFixture.makeVault(coins: [atom])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        XCTAssertEqual(model.amount, atom.balanceDecimal)
    }

    /// Pin: legacy `toString()` returned `SWITCH:<thorAddress>`.
    func testToStringMatchesLegacyMemo() {
        let atom = FunctionCallFixture.makeATOM()
        let vault = FunctionCallFixture.makeVault(coins: [atom])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        model.thorAddress = "thor1switchtarget"
        XCTAssertEqual(model.toString(), "SWITCH:thor1switchtarget")
    }

    func testToDictionaryIncludesAllKeys() {
        let atom = FunctionCallFixture.makeATOM()
        let vault = FunctionCallFixture.makeVault(coins: [atom])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        model.thorAddress = "thor1switch"
        model.destinationAddress = "cosmos1inbound"
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["destinationAddress"], "cosmos1inbound")
        XCTAssertEqual(dict["thorchainAddress"], "thor1switch")
        XCTAssertEqual(dict["memo"], "SWITCH:thor1switch")
    }

    func testHandleDestinationAddressResultWritesField() {
        let atom = FunctionCallFixture.makeATOM()
        let vault = FunctionCallFixture.makeVault(coins: [atom])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        model.handle(destinationAddressResult: AddressResult(address: "cosmos1pasted"))
        XCTAssertEqual(model.destinationAddress, "cosmos1pasted")
    }

    func testHandleThorAddressResultWritesField() {
        let atom = FunctionCallFixture.makeATOM()
        let vault = FunctionCallFixture.makeVault(coins: [atom])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        model.handle(thorAddressResult: AddressResult(address: "thor1pasted"))
        XCTAssertEqual(model.thorAddress, "thor1pasted")
    }
}
