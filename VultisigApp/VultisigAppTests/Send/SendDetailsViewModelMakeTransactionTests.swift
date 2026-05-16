//
//  SendDetailsViewModelMakeTransactionTests.swift
//  VultisigAppTests
//
//  Coverage for `SendDetailsViewModel.makeTransaction()` — the Continue
//  hand-off. Pins every form field's propagation into the immutable
//  `SendTransaction`, plus the three pilot decisions (plain dict, required
//  vault, custom-gas preservation).
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendDetailsViewModelMakeTransactionTests: XCTestCase {

    // MARK: - Happy path: every field propagates

    func testMakeTransactionPopulatesEveryFieldFromVMState() throws {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.toAddress = "0xdead"
        vm.toAddressLabel = "vitalik.eth"
        vm.amount = "0.5"
        vm.amountInFiat = "1200"
        vm.memo = "gift"
        vm.gas = BigInt(50_000_000_000)
        vm.fee = BigInt(1_050_000_000_000_000)
        vm.feeMode = .fast
        vm.estimatedGasLimit = BigInt(21_000)
        vm.sendMaxAmount = false
        vm.isFastVault = true
        vm.isStakingOperation = false
        vm.transactionType = .unspecified

        let tx = try vm.makeTransaction()

        XCTAssertEqual(tx.coin, vm.coin)
        XCTAssertEqual(tx.vault.pubKeyECDSA, vm.vault.pubKeyECDSA)
        XCTAssertEqual(tx.fromAddress, vm.fromAddress)
        XCTAssertEqual(tx.toAddress, "0xdead")
        XCTAssertEqual(tx.toAddressLabel, "vitalik.eth")
        XCTAssertEqual(tx.amount, "0.5")
        XCTAssertEqual(tx.amountInFiat, "1200")
        XCTAssertEqual(tx.memo, "gift")
        XCTAssertEqual(tx.gas, BigInt(50_000_000_000))
        XCTAssertEqual(tx.fee, BigInt(1_050_000_000_000_000))
        XCTAssertEqual(tx.feeMode, .fast)
        XCTAssertEqual(tx.estimatedGasLimit, BigInt(21_000))
        XCTAssertFalse(tx.sendMaxAmount)
        XCTAssertTrue(tx.isFastVault)
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertEqual(tx.transactionType, .unspecified)
    }

    // MARK: - Pilot decisions baked in

    func testMakeTransactionDictIsPlainStringStringNotThreadSafe() throws {
        let vm = SendFormFixture.make()
        vm.toAddress = "addr"
        vm.amount = "1.0"
        vm.memoFunctionDictionary = ["pool": "BTC.BTC", "asset": "USDC"]

        let tx = try vm.makeTransaction()

        // Decision 1: the new struct's dict is `[String: String]`, not
        // `ThreadSafeDictionary`. Subscript-readable, no wrapper methods.
        XCTAssertEqual(tx.memoFunctionDictionary["pool"], "BTC.BTC")
        XCTAssertEqual(tx.memoFunctionDictionary["asset"], "USDC")
        XCTAssertEqual(tx.memoFunctionDictionary.count, 2)
    }

    func testMakeTransactionVaultIsRequiredAndNonOptional() throws {
        let vault = SendFormFixture.makeVault()
        let vm = SendFormFixture.make(vault: vault)
        vm.toAddress = "addr"
        vm.amount = "1.0"

        let tx = try vm.makeTransaction()

        // Decision 2: `tx.vault` is `Vault`, not `Vault?`. Compile-time
        // guarantee; we just confirm it round-trips at runtime.
        XCTAssertEqual(tx.vault.pubKeyECDSA, vault.pubKeyECDSA)
    }

    func testMakeTransactionPreservesCustomGasLimit() throws {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.toAddress = "0xdead"
        vm.amount = "0.5"
        vm.customGasLimit = BigInt(75_000)

        let tx = try vm.makeTransaction()

        // Decision 3: custom gas survives the hand-off so Verify refresh
        // can preserve it via `tx.with(...)`.
        XCTAssertEqual(tx.customGasLimit, BigInt(75_000))
        XCTAssertEqual(tx.gasLimit, BigInt(75_000), "gasLimit accessor prefers customGasLimit when set.")
    }

    func testMakeTransactionPreservesCustomByteFee() throws {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.toAddress = "bc1qdead"
        vm.amount = "0.01"
        vm.customByteFee = BigInt(120)

        let tx = try vm.makeTransaction()

        XCTAssertEqual(tx.customByteFee, BigInt(120))
        XCTAssertEqual(tx.byteFee, BigInt(120))
    }

    // MARK: - feeCoin precomputation

    func testMakeTransactionFeeCoinIsSelfForNativeSource() throws {
        let eth = SendFormFixture.makeETH()
        let vm = SendFormFixture.make(coin: eth)
        vm.toAddress = "0xdead"
        vm.amount = "0.1"
        let tx = try vm.makeTransaction()
        XCTAssertEqual(tx.feeCoin, eth)
    }

    func testMakeTransactionFeeCoinResolvesToVaultNativeSiblingForERC20() throws {
        let eth = SendFormFixture.makeETH()
        let usdc = SendFormFixture.makeUSDC()
        let vault = SendFormFixture.makeVault(coins: [eth, usdc])
        let vm = SendFormFixture.make(coin: usdc, vault: vault)
        vm.toAddress = "0xdead"
        vm.amount = "100"

        let tx = try vm.makeTransaction()

        XCTAssertEqual(tx.feeCoin.ticker, "ETH",
                       "ERC20 source on an EVM chain should use the vault's native sibling for fee display.")
    }

    func testMakeTransactionFeeCoinFallsBackToCoinWhenVaultHasNoNative() throws {
        let usdc = SendFormFixture.makeUSDC()
        let vault = SendFormFixture.makeVault() // no ETH in vault
        let vm = SendFormFixture.make(coin: usdc, vault: vault)
        vm.toAddress = "0xdead"
        vm.amount = "100"

        let tx = try vm.makeTransaction()

        XCTAssertEqual(tx.feeCoin, usdc)
    }

    // MARK: - Function-call side channels

    func testMakeTransactionIncludesWasmContractPayloadWhenSet() throws {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeATOM())
        vm.toAddress = "cosmos1abc"
        vm.amount = "1.0"
        let payload = WasmExecuteContractPayload(
            senderAddress: "cosmos1abc",
            contractAddress: "cosmos1contract",
            executeMsg: "{}",
            coins: []
        )
        vm.wasmContractPayload = payload

        let tx = try vm.makeTransaction()

        XCTAssertEqual(tx.wasmContractPayload?.contractAddress, "cosmos1contract")
    }

    // MARK: - Throws on invalid form

    func testMakeTransactionThrowsOnEmptyToAddress() {
        let vm = SendFormFixture.make()
        vm.amount = "1.0"
        XCTAssertThrowsError(try vm.makeTransaction()) { error in
            XCTAssertTrue(error is SendDetailsViewModel.MakeTransactionError)
        }
    }

    func testMakeTransactionThrowsOnZeroAmount() {
        let vm = SendFormFixture.make()
        vm.toAddress = "addr"
        vm.amount = "0"
        XCTAssertThrowsError(try vm.makeTransaction())
    }

    func testMakeTransactionThrowsOnEmptyAmount() {
        let vm = SendFormFixture.make()
        vm.toAddress = "addr"
        vm.amount = ""
        XCTAssertThrowsError(try vm.makeTransaction())
    }
}
