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

    /// Pin: amount > coin.balanceDecimal must fail the submit-time gate.
    /// Closes the latent over-balance hole — the no-arg `var
    /// isTheFormValid` only checked `amount > 0 && !destinationAddress.isEmpty`.
    func testFormValidityRejectsAmountOverBalance() {
        let atom = FunctionCallFixture.makeATOM(rawBalance: "1000000")
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [atom, rune])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        model.destinationAddress = FunctionCallFixture.cosmosAddress
        model.amount = atom.balanceDecimal + 1
        XCTAssertFalse(model.isFormValid(for: atom))
    }

    /// Pin: an invalid Cosmos destination address must fail the
    /// submit-time gate. Closes the P1 regression where the no-arg
    /// `var isTheFormValid` accepted any non-empty string for the
    /// GAIA inbound destination.
    func testFormValidityRejectsInvalidCosmosDestination() {
        let atom = FunctionCallFixture.makeATOM()
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [atom, rune])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        model.destinationAddress = "thor1abc" // wrong chain prefix for GAIA source
        model.amount = 0.001
        XCTAssertFalse(model.isFormValid(for: atom))
        XCTAssertNotNil(model.destinationAddressError(for: atom))
    }
}
