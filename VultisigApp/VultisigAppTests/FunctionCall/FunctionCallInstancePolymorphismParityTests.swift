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

    func testRebondParity() {
        let model = FunctionCallReBond()
        model.nodeAddress = "thor1node"
        model.newAddress = "thor1new"
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let instance = FunctionCallInstance.rebond(model)

        let tx = instance.toSendTransaction(coin: coin, vault: vault, gas: 100)
        XCTAssertEqual(tx.memo, "REBOND:thor1node:thor1new")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.amount, "0")           // REBOND burns zero RUNE
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(instance.toAddress)
        XCTAssertEqual(instance.amount, .zero)

        assertForwardingParity(instance, forwardsTo: model, coin: coin, vault: vault, gas: 100)
    }

    func testBondMayaParity() {
        let model = FunctionCallBondMayaChain(assets: [])
        model.selectedAsset = IdentifiableString(value: "BTC.BTC")
        model.fee = 5000
        model.nodeAddress = "maya1bondnode"
        let coin = FunctionCallFixture.makeCoin(.mayaChain, ticker: "CACAO", decimals: 8, isNative: true)
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let instance = FunctionCallInstance.bondMaya(model)

        let tx = instance.toSendTransaction(coin: coin, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "BOND:BTC.BTC:5000:maya1bondnode")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(instance.toAddress)

        assertForwardingParity(instance, forwardsTo: model, coin: coin, vault: vault, gas: 0)
    }

    func testUnbondMayaParity() {
        let model = FunctionCallUnbondMayaChain(assets: [])
        model.selectedAsset = IdentifiableString(value: "BTC.BTC")
        model.fee = 1234
        model.nodeAddress = "maya1abc"
        let coin = FunctionCallFixture.makeCoin(.mayaChain, ticker: "CACAO", decimals: 8, isNative: true)
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let instance = FunctionCallInstance.unbondMaya(model)

        let tx = instance.toSendTransaction(coin: coin, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "UNBOND:BTC.BTC:1234:maya1abc")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(instance.toAddress)
        XCTAssertEqual(instance.amount, 1 / pow(Decimal(10), 8))

        assertForwardingParity(instance, forwardsTo: model, coin: coin, vault: vault, gas: 0)
    }

    func testLeaveParity() {
        let model = FunctionCallLeave()
        model.nodeAddress = "thor1abc"
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let instance = FunctionCallInstance.leave(model)

        let tx = instance.toSendTransaction(coin: coin, vault: vault, gas: 100)
        XCTAssertEqual(tx.memo, "LEAVE:thor1abc")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.amount, "0")
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(instance.toAddress)
        XCTAssertEqual(instance.amount, .zero)

        assertForwardingParity(instance, forwardsTo: model, coin: coin, vault: vault, gas: 100)
    }

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

    func testVoteParity() {
        let model = FunctionCallVote()
        model.selectedMemo = .yes
        model.proposalID = 42
        let coin = FunctionCallFixture.makeCoin(.dydx, ticker: "DYDX", decimals: 18, isNative: true)
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let instance = FunctionCallInstance.vote(model)

        let tx = instance.toSendTransaction(coin: coin, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "DYDX_VOTE:Yes:42")
        XCTAssertEqual(tx.transactionType, .vote)
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(instance.toAddress)
        XCTAssertEqual(instance.amount, .zero)

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

    func testMergeParity() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let model = FunctionCallCosmosMerge(coin: rune, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.KUJI")
        model.destinationAddress = "thor1mergeaddress"
        let instance = FunctionCallInstance.merge(model)

        let tx = instance.toSendTransaction(coin: rune, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "merge:THOR.KUJI")
        XCTAssertEqual(tx.transactionType, .thorMerge)
        XCTAssertEqual(tx.toAddress, "thor1mergeaddress")
        XCTAssertEqual(instance.toAddress, "thor1mergeaddress")

        assertForwardingParity(instance, forwardsTo: model, coin: rune, vault: vault, gas: 0)
    }

    func testUnmergeParity() {
        let ruji = FunctionCallFixture.makeRUJI()
        let vault = FunctionCallFixture.makeVault(coins: [FunctionCallFixture.makeRUNE(), ruji])
        let model = FunctionCallCosmosUnmerge(coin: ruji, vault: vault)
        model.selectedToken = IdentifiableString(value: "THOR.RUJI")
        model.destinationAddress = "thor1mergecontract"
        model.amount = 1
        let instance = FunctionCallInstance.unmerge(model)

        let tx = instance.toSendTransaction(coin: ruji, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "unmerge:thor.ruji:100000000")
        XCTAssertEqual(tx.transactionType, .thorUnmerge)
        XCTAssertEqual(tx.toAddress, "thor1mergecontract")
        XCTAssertEqual(instance.toAddress, "thor1mergecontract")
        // Preserved: the instance never surfaces unmerge's own error slot.
        XCTAssertNil(instance.customErrorMessage)

        assertForwardingParity(instance, forwardsTo: model, coin: ruji, vault: vault, gas: 0)
    }

    func testTheSwitchParity() {
        let atom = FunctionCallFixture.makeATOM()
        let vault = FunctionCallFixture.makeVault(coins: [atom, FunctionCallFixture.makeRUNE()])
        let model = FunctionCallCosmosSwitch(coin: atom, vault: vault)
        model.thorAddress = "thor1switchtarget"
        model.destinationAddress = "cosmos1inbound"
        let instance = FunctionCallInstance.theSwitch(model)

        let tx = instance.toSendTransaction(coin: atom, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "SWITCH:thor1switchtarget")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.toAddress, "cosmos1inbound")
        XCTAssertEqual(instance.toAddress, "cosmos1inbound")

        assertForwardingParity(instance, forwardsTo: model, coin: atom, vault: vault, gas: 0)
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

    func testSecuredAssetParity() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        // No initialize() — offline; toAddress stays "".
        let model = FunctionCallSecuredAsset(coin: rune, vault: vault)
        model.thorAddress = "thor1secureplus"
        let instance = FunctionCallInstance.securedAsset(model)

        let tx = instance.toSendTransaction(coin: rune, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "SECURE+:thor1secureplus")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertNil(instance.toAddress)

        assertForwardingParity(instance, forwardsTo: model, coin: rune, vault: vault, gas: 0)
    }

    func testWithdrawSecuredAssetParity() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        // No initialize() — offline.
        let model = FunctionCallWithdrawSecuredAsset(coin: rune, vault: vault)
        model.destinationAddress = "0xL1DestAddr"
        let instance = FunctionCallInstance.withdrawSecuredAsset(model)

        let tx = instance.toSendTransaction(coin: rune, vault: vault, gas: 0)
        XCTAssertEqual(tx.memo, "SECURE-:0xL1DestAddr")
        XCTAssertEqual(tx.transactionType, .unspecified)
        // Withdraw signs via MsgDeposit — toAddress is intentionally empty
        // even though `destinationAddress` is set.
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertNil(instance.toAddress)

        assertForwardingParity(instance, forwardsTo: model, coin: rune, vault: vault, gas: 0)
    }
}
