//
//  FunctionCallCosmosIBCTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallCosmosIBCTests: XCTestCase {

    func testInitSeedsAmountFromCoinBalance() {
        let kuji = FunctionCallFixture.makeKUJI(rawBalance: "5000000")
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        XCTAssertEqual(model.amount, kuji.balanceDecimal)
    }

    /// Pin: legacy `toString()` shape was
    /// `<destChain.name>:<channel>:<destAddress>[:<memo>]` — the
    /// optional `fnCall` suffix gets appended only when non-empty.
    func testToStringWithoutOptionalMemoMatchesLegacy() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        model.selectedChainObject = .gaiaChain
        model.destinationAddress = "cosmos1abc"
        // Don't set fnCall — legacy omits the optional segment.
        let memo = model.toString()
        XCTAssertTrue(memo.hasPrefix("\(Chain.gaiaChain.name):"))
        XCTAssertTrue(memo.hasSuffix(":cosmos1abc"))
        XCTAssertFalse(memo.hasSuffix(":"))
    }

    func testToStringWithOptionalMemoAppendsSegment() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        model.selectedChainObject = .gaiaChain
        model.destinationAddress = "cosmos1abc"
        model.fnCall = "hello-ibc"
        XCTAssertTrue(model.toString().hasSuffix(":hello-ibc"))
    }

    func testToDictionaryIncludesAllKeys() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        model.selectedChainObject = .gaiaChain
        model.destinationAddress = "cosmos1abc"
        let dict = model.toDictionary().allItems()
        XCTAssertNotNil(dict["destinationChain"])
        XCTAssertNotNil(dict["destinationChannel"])
        XCTAssertEqual(dict["destinationAddress"], "cosmos1abc")
        XCTAssertNotNil(dict["memo"])
    }

    func testHandleAddressResultWritesDestinationAddress() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        model.handle(addressResult: AddressResult(address: "cosmos1pasted"))
        XCTAssertEqual(model.destinationAddress, "cosmos1pasted")
    }

    func testToSendTransactionTypeIsIBCTransfer() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        model.selectedChainObject = .gaiaChain
        model.destinationAddress = "cosmos1abc"
        let tx = model.toSendTransaction(coin: kuji, vault: vault, gas: 0)
        XCTAssertEqual(tx.transactionType, .ibcTransfer)
        XCTAssertEqual(tx.toAddress, "cosmos1abc")
    }

    /// Pin: amount > coin.balanceDecimal must fail the submit-time gate.
    /// Closes the latent over-balance hole — the no-arg `var
    /// isTheFormValid` only checked `isChainSelected && amount > 0`.
    func testFormValidityRejectsAmountOverBalance() {
        let kuji = FunctionCallFixture.makeKUJI(rawBalance: "1000000")
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        model.selectedChainObject = .gaiaChain
        model.destinationAddress = FunctionCallFixture.cosmosAddress
        model.selectedChain = IdentifiableString(value: "\(Chain.gaiaChain.name) \(Chain.gaiaChain.ticker)")
        model.amount = kuji.balanceDecimal + 1
        XCTAssertFalse(model.isFormValid(for: kuji))
    }

    /// Pin: an invalid Cosmos destination address must fail the
    /// submit-time gate. Closes the regression where the no-arg
    /// `var isTheFormValid` accepted any non-empty string and the
    /// existing `FunctionCallAddressValidation.errorForCosmos` helper
    /// was never wired in.
    func testFormValidityRejectsInvalidCosmosDestination() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        model.selectedChainObject = .gaiaChain
        model.selectedChain = IdentifiableString(value: "\(Chain.gaiaChain.name) \(Chain.gaiaChain.ticker)")
        model.destinationAddress = "thor1abc" // wrong chain prefix for GAIA destination
        model.amount = 0.001
        XCTAssertFalse(model.isFormValid(for: kuji))
        XCTAssertNotNil(model.destinationAddressValidationError)
    }
}
