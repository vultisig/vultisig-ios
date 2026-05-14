//
//  SendCryptoVerifyViewModelTests.swift
//  VultisigAppTests
//
//  Coverage for the Verify VM rewritten in #4347 Phase C — the one that holds
//  `@Published var transaction: SendTransaction` and refreshes via `.with(...)`.
//  Until now this VM only had regression coverage via `TonSendTransactionTests`;
//  these tests cover its dedicated state surface (init, form-validity gating,
//  signButton-disabled gating, validateBalanceWithFee, validateSecurityScanner).
//
//  The async methods (`loadGasInfoForSending`, `validateForm`, `scan`) hit
//  `BlockChainService.shared` + `KeysignPayloadFactory` + `BalanceService.shared`
//  directly today; mocking them requires DI which is a larger refactor and
//  out of scope here. The form-VM PR series eventually replaces this VM
//  (Phase 2c/d migrates Verify to the same `SendInteractor` injection
//  pattern the new `SendDetailsViewModel` uses, at which point these tests
//  can be extended).
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendCryptoVerifyViewModelTests: XCTestCase {

    // MARK: - Init

    func testInitWithTransactionSetsTransactionField() throws {
        let tx = try makeTransaction()
        let vm = SendCryptoVerifyViewModel(transaction: tx)
        XCTAssertEqual(vm.transaction.coin, tx.coin)
        XCTAssertEqual(vm.transaction.toAddress, tx.toAddress)
        XCTAssertEqual(vm.transaction.amount, tx.amount)
    }

    func testInitDefaultsForVMState() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        XCTAssertFalse(vm.isCalculatingFee)
        XCTAssertFalse(vm.isAddressCorrect)
        XCTAssertFalse(vm.isAmountCorrect)
        XCTAssertFalse(vm.showAlert)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.errorMessage, "")
        XCTAssertFalse(vm.hasBalanceError)
        XCTAssertEqual(vm.fastVaultPassword, "")
        XCTAssertFalse(vm.showSecurityScannerSheet)
    }

    // MARK: - isValidForm gating

    func testIsValidFormTrueWhenBothChecksAreOn() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertTrue(vm.isValidForm)
    }

    func testIsValidFormFalseWhenAddressUnchecked() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = false
        vm.isAmountCorrect = true
        XCTAssertFalse(vm.isValidForm)
    }

    func testIsValidFormFalseWhenAmountUnchecked() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = false
        XCTAssertFalse(vm.isValidForm)
    }

    // MARK: - signButtonDisabled gating

    func testSignButtonDisabledWhenInvalidForm() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = false
        vm.isAmountCorrect = false
        XCTAssertTrue(vm.signButtonDisabled)
    }

    func testSignButtonDisabledWhenLoading() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        vm.isLoading = true
        XCTAssertTrue(vm.signButtonDisabled)
    }

    func testSignButtonDisabledWhenHasBalanceError() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        vm.hasBalanceError = true
        XCTAssertTrue(vm.signButtonDisabled)
    }

    func testSignButtonEnabledOnHappyPath() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertFalse(vm.signButtonDisabled)
    }

    // MARK: - validateBalanceWithFee

    func testValidateBalanceWithFeeNoErrorWhenAmountPlusFeeFitsNative() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000") // 1 ETH
        let tx = try makeTransaction(coin: eth, amount: "0.5", fee: BigInt(stringLiteral: "10000000000000000"))
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertFalse(vm.hasBalanceError)
        XCTAssertFalse(vm.showAlert)
        XCTAssertEqual(vm.errorMessage, "")
    }

    func testValidateBalanceWithFeeSetsErrorWhenNativeBalanceExceeded() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "100000000000000000") // 0.1 ETH
        let tx = try makeTransaction(coin: eth, amount: "0.5", fee: BigInt(stringLiteral: "10000000000000000"))
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError)
        XCTAssertTrue(vm.showAlert)
        XCTAssertFalse(vm.isAmountCorrect)
        XCTAssertEqual(vm.errorMessage, "walletBalanceExceededError")
    }

    func testValidateBalanceWithFeeSetsErrorForSendMaxWhenFeeExceedsBalance() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "5000000000000000") // 0.005 ETH
        var tx = try makeTransaction(coin: eth, amount: "0", fee: BigInt(stringLiteral: "10000000000000000"))
        tx = SendTransaction(
            coin: tx.coin, vault: tx.vault, fromAddress: tx.fromAddress,
            toAddress: tx.toAddress, toAddressLabel: nil,
            amount: tx.amount, amountInFiat: "", memo: "",
            gas: tx.gas, fee: tx.fee, feeMode: .default,
            estimatedGasLimit: nil, customGasLimit: nil, customByteFee: nil,
            sendMaxAmount: true,
            isFastVault: false, isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: eth
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError)
        XCTAssertEqual(vm.errorMessage, "walletBalanceExceededError")
    }

    // MARK: - validateSecurityScanner

    func testValidateSecurityScannerReturnsTrueWhenStateIdle() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.securityScannerState = .idle
        XCTAssertTrue(vm.validateSecurityScanner())
        XCTAssertFalse(vm.showSecurityScannerSheet)
    }

    // MARK: - feeMode pin (regression for #4347 bug fix)

    func testTransactionFeeModePropagatesThroughInit() throws {
        // Confirms the immutable struct carries `feeMode` from construction —
        // pre-#4347 the field existed but Verify refresh hardcoded
        // `feeMode: .default` instead of reading `tx.feeMode`.
        let tx = try makeTransaction(feeMode: .fast)
        let vm = SendCryptoVerifyViewModel(transaction: tx)
        XCTAssertEqual(vm.transaction.feeMode, .fast)
    }

    // MARK: - .with() refresh preserves customGasLimit (regression pin)

    func testRefreshViaWithPreservesCustomGasLimit() throws {
        // The Verify VM updates `transaction` via `with(...)` on refresh. This
        // pin guards the customGasLimit preservation contract — a regression
        // here would re-introduce the bug where user-pinned EVM gas got
        // dropped on the 60s refresh.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let vault = try TestStore.makeVault()
        let originalTx = SendTransaction(
            coin: eth, vault: vault, fromAddress: eth.address,
            toAddress: "0xabc", toAddressLabel: nil,
            amount: "0.5", amountInFiat: "", memo: "",
            gas: BigInt(stringLiteral: "20000000000"),
            fee: BigInt(stringLiteral: "420000000000000"),
            feeMode: .fast,
            estimatedGasLimit: BigInt(21_000),
            customGasLimit: BigInt(50_000),
            customByteFee: nil,
            sendMaxAmount: false,
            isFastVault: false, isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: eth
        )
        let vm = SendCryptoVerifyViewModel(transaction: originalTx)

        // Simulate what loadGasInfoForSending does internally on refresh.
        vm.transaction = vm.transaction.with(
            gas: BigInt(stringLiteral: "30000000000"),
            fee: BigInt(stringLiteral: "630000000000000")
        )

        XCTAssertEqual(vm.transaction.customGasLimit, BigInt(50_000), "customGasLimit must survive Verify refresh")
        XCTAssertEqual(vm.transaction.gas, BigInt(stringLiteral: "30000000000"))
        XCTAssertEqual(vm.transaction.gasLimit, BigInt(50_000))
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    private func makeTransaction(
        coin: Coin? = nil,
        amount: String = "0.1",
        fee: BigInt = BigInt(stringLiteral: "1000000000000000"),
        feeMode: FeeMode = .default
    ) throws -> SendTransaction {
        let vault = try TestStore.makeVault()
        let coinToUse = coin ?? makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                                         rawBalance: "1000000000000000000")
        return SendTransaction(
            coin: coinToUse,
            vault: vault,
            fromAddress: coinToUse.address,
            toAddress: "0x0000000000000000000000000000000000000001",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: "",
            gas: BigInt.zero,
            fee: fee,
            feeMode: feeMode,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isFastVault: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coinToUse
        )
    }
}
