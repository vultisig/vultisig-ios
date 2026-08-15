//
//  FunctionCallInstancePolymorphismParityTests.swift
//  VultisigAppTests
//
//  Guards the "Replace Conditional with Polymorphism" collapse of
//  `FunctionCallInstance`: every accessor now forwards through the single
//  `model` sub-model instead of re-`switch`ing the 13-case enum.
//
//  The critical invariant is that `toSendTransaction` — which feeds
//  signing — stays byte-identical per case. Each test builds a case with
//  deterministic state, then asserts the instance-produced `SendTransaction`
//  equals the sub-model's own output (the captured baseline) AND pins the
//  keysign-relevant fields (memo / transactionType / toAddress) to golden
//  literals. The shared helper additionally checks that `description`,
//  `amount`, `toAddress`, `customErrorMessage` and `isFormValid(for:)` all
//  route to the same sub-model.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallInstancePolymorphismParityTests: XCTestCase {

    // MARK: - Shared forwarding-parity assertion

    /// Asserts every forwarded accessor on `instance` routes to `subModel`,
    /// with `toSendTransaction` byte-identical to the sub-model's own output.
    private func assertForwardingParity(
        _ instance: FunctionCallInstance,
        forwardsTo subModel: any FunctionCallSubModel,
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let viaInstance = instance.toSendTransaction(coin: coin, vault: vault, gas: gas)
        let baseline = subModel.toSendTransaction(coin: coin, vault: vault, gas: gas)

        // Byte-identical dispatch: the polymorphic path produces the exact
        // same signing input as calling the sub-model directly.
        XCTAssertEqual(
            viaInstance,
            baseline,
            "toSendTransaction must be byte-identical to the sub-model output",
            file: file,
            line: line
        )

        XCTAssertEqual(instance.description, subModel.description, file: file, line: line)
        XCTAssertEqual(instance.amount, subModel.amount, file: file, line: line)
        XCTAssertEqual(instance.toAddress, subModel.resolvedToAddress, file: file, line: line)
        XCTAssertEqual(instance.customErrorMessage, subModel.submitErrorMessage, file: file, line: line)
        XCTAssertEqual(instance.isFormValid(for: coin), subModel.isFormValid(for: coin), file: file, line: line)
    }

    // MARK: - Per-case parity

    func testCustomParity() {
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let model = FunctionCallCustom(coin: coin, vault: vault)
        model.custom = "arbitrary-memo-string"
        let instance = FunctionCallInstance.custom(model)

        let tx = instance.toSendTransaction(coin: coin, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "arbitrary-memo-string")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(instance.toAddress)
        XCTAssertNil(instance.customErrorMessage)

        assertForwardingParity(instance, forwardsTo: model, coin: coin, vault: vault, gas: 0)
    }

    func testCosmosIBCParity() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let model = FunctionCallCosmosIBC(coin: kuji, vault: vault)
        model.selectedChainObject = .gaiaChain
        model.destinationAddress = "cosmos1abc"
        let instance = FunctionCallInstance.cosmosIBC(model)

        let tx = instance.toSendTransaction(coin: kuji, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, model.toString())
        XCTAssertEqual(tx.transactionType, .ibcTransfer)
        XCTAssertEqual(tx.toAddress, "cosmos1abc")
        XCTAssertEqual(instance.toAddress, "cosmos1abc")

        assertForwardingParity(instance, forwardsTo: model, coin: kuji, vault: vault, gas: 0)
    }

    func testAddThorLPParity() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        // No initialize() — keeps the inbound fetch offline; toAddress stays "".
        let model = FunctionCallAddThorLP(coin: rune, vault: vault)
        model.selectedPool = IdentifiableString(value: "BTC.BTC")
        model.pairedAddress = "thor1paired"
        let instance = FunctionCallInstance.addThorLP(model)

        let tx = instance.toSendTransaction(coin: rune, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, model.toString())
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertNil(instance.toAddress)

        assertForwardingParity(instance, forwardsTo: model, coin: rune, vault: vault, gas: 0)
    }
}
