//
//  SendDetailsViewModelTests.swift
//  VultisigAppTests
//
//  Form-state lifecycle tests for the new @Observable form VM. Covers init,
//  field updates, derived-state propagation, async refresh paths, custom-gas
//  preservation, zero-amount state reset, and the feeMode bug-fix regression.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendDetailsViewModelTests: XCTestCase {

    // MARK: - Init

    func testInitWithCoinAndVaultSetsBaseline() {
        let vm = SendFormFixture.make()
        XCTAssertEqual(vm.amount, "")
        XCTAssertEqual(vm.toAddress, "")
        XCTAssertEqual(vm.memo, "")
        XCTAssertEqual(vm.feeMode, .default)
        XCTAssertFalse(vm.sendMaxAmount)
        XCTAssertFalse(vm.isFastVault)
        XCTAssertNil(vm.customGasLimit)
        XCTAssertNil(vm.customByteFee)
        XCTAssertTrue(vm.memoFunctionDictionary.isEmpty)
    }

    func testFromAddressMirrorsCoinAddress() {
        let eth = SendFormFixture.makeETH()
        let vm = SendFormFixture.make(coin: eth)
        XCTAssertEqual(vm.fromAddress, eth.address)
    }

    func testFeeCoinResolvesToSelfForNativeSource() {
        let eth = SendFormFixture.makeETH()
        let vm = SendFormFixture.make(coin: eth)
        XCTAssertEqual(vm.feeCoin, eth)
    }

    func testFeeCoinFallsBackToCoinWhenVaultHasNoNative() {
        // Vault has no ETH coin, so the USDC source falls back to itself.
        let vm = SendFormFixture.make(coin: SendFormFixture.makeUSDC())
        XCTAssertEqual(vm.feeCoin, vm.coin)
    }

    // MARK: - Zero-amount state reset (Phase D lesson)

    func testEmptyAmountClearsDerivedStateOnLoadGasInfo() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(interactor: interactor)
        // Seed prior state.
        vm.amount = "1.0"
        vm.gas = BigInt(50)
        vm.fee = BigInt(5000)
        vm.estimatedGasLimit = BigInt(21000)

        // Phase D lesson: clearing the amount must clear derived fields.
        vm.amount = ""
        await vm.loadGasInfo()

        XCTAssertEqual(vm.gas, .zero)
        XCTAssertEqual(vm.fee, .zero)
        XCTAssertNil(vm.estimatedGasLimit)
        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 0,
                       "loadGasInfo must short-circuit on empty amount — no service calls.")
    }

    func testZeroAmountShortCircuitsLoadGasInfo() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(interactor: interactor)
        vm.amount = "0"
        await vm.loadGasInfo()
        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 0)
        XCTAssertEqual(interactor.calculateEVMFeeCalls.count, 0)
    }

    // MARK: - feeMode bug-fix regression

    func testLoadGasInfoForwardsFeeMode() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        vm.amount = "0.1"
        vm.toAddress = "0xabc"
        vm.feeMode = .fast

        await vm.loadGasInfo()

        XCTAssertEqual(interactor.fetchChainSpecificCalls.last?.feeMode, .fast,
                       "loadGasInfo must thread tx.feeMode through fetchChainSpecific (regression for #4347's feeMode bug fix).")
        XCTAssertEqual(interactor.calculateEVMFeeCalls.last?.feeMode, .fast,
                       "calculateEVMFee must receive the user's pinned feeMode, not .default.")
    }

    func testChangingFeeModeAndRefetchingProducesNewCalls() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        vm.amount = "0.1"
        vm.toAddress = "0xabc"

        vm.feeMode = .default
        await vm.loadGasInfo()
        vm.feeMode = .fast
        await vm.loadGasInfo()

        let modes = interactor.fetchChainSpecificCalls.map { $0.feeMode }
        XCTAssertEqual(modes, [.default, .fast])
    }

    // MARK: - Custom gas preservation

    func testCustomGasLimitPinnedThroughLoadGasInfo() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        vm.amount = "0.1"
        vm.toAddress = "0xabc"
        vm.customGasLimit = BigInt(50_000)

        await vm.loadGasInfo()

        XCTAssertEqual(vm.customGasLimit, BigInt(50_000),
                       "User-pinned custom gas limit must survive a Verify refresh.")
    }

    func testCustomByteFeePinnedThroughLoadGasInfo() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC(), interactor: interactor)
        vm.amount = "0.01"
        vm.toAddress = "bc1qabc"
        vm.customByteFee = BigInt(80)

        await vm.loadGasInfo()

        XCTAssertEqual(vm.customByteFee, BigInt(80))
        XCTAssertEqual(vm.byteFee, BigInt(80),
                       "byteFee accessor must prefer the user-pinned customByteFee over the chain-fetched gas.")
    }

    // MARK: - sendMaxAmount semantics

    func testSetSendMaxAmountTrueForUTXOSetsFlag() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.sendMaxAmount = true
        XCTAssertTrue(vm.sendMaxAmount)
    }

    // MARK: - Pending transaction state

    func testInitializePendingTransactionStateForCosmosChain() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeATOM())
        vm.initializePendingTransactionState(for: .gaiaChain)
        XCTAssertTrue(vm.isCheckingPendingTransactions)
    }

    func testInitializePendingTransactionStateClearsForNonCosmosChain() {
        let vm = SendFormFixture.make()
        vm.isCheckingPendingTransactions = true
        vm.hasPendingTransaction = true
        vm.pendingTransactionCountdown = 5
        vm.initializePendingTransactionState(for: .bitcoin)
        XCTAssertFalse(vm.isCheckingPendingTransactions)
        XCTAssertFalse(vm.hasPendingTransaction)
        XCTAssertEqual(vm.pendingTransactionCountdown, 0)
    }

    // MARK: - Reset

    func testResetClearsEveryFormFieldButPreservesVaultAndNewCoin() {
        let originalCoin = SendFormFixture.makeETH()
        let newCoin = SendFormFixture.makeBTC()
        let vm = SendFormFixture.make(coin: originalCoin)
        vm.amount = "1.0"
        vm.toAddress = "0xabc"
        vm.memo = "test"
        vm.gas = BigInt(50)
        vm.fee = BigInt(5000)
        vm.customGasLimit = BigInt(50_000)
        vm.memoFunctionDictionary = ["pool": "BTC.BTC"]

        vm.reset(to: newCoin)

        XCTAssertEqual(vm.coin, newCoin)
        XCTAssertEqual(vm.fromAddress, newCoin.address)
        XCTAssertEqual(vm.amount, "")
        XCTAssertEqual(vm.toAddress, "")
        XCTAssertEqual(vm.memo, "")
        XCTAssertEqual(vm.gas, .zero)
        XCTAssertEqual(vm.fee, .zero)
        XCTAssertNil(vm.customGasLimit)
        XCTAssertTrue(vm.memoFunctionDictionary.isEmpty)
    }

    // MARK: - Fast vault

    func testLoadFastVaultEligibleSetsFlag() async {
        let interactor = MockSendInteractor()
        interactor.loadFastVaultResult = true
        let vm = SendFormFixture.make(interactor: interactor)

        await vm.loadFastVault()

        XCTAssertTrue(vm.isFastVault)
        XCTAssertEqual(interactor.loadFastVaultCalls.count, 1)
    }

    func testLoadFastVaultIneligibleLeavesFlagFalse() async {
        let interactor = MockSendInteractor()
        interactor.loadFastVaultResult = false
        let vm = SendFormFixture.make(interactor: interactor)

        await vm.loadFastVault()

        XCTAssertFalse(vm.isFastVault)
    }

    // MARK: - Amount sync validation (Phase 2b)

    func testValidateAmountAcceptsValidDecimal() {
        let vm = SendFormFixture.make()
        vm.validateAmount("0.5")
        XCTAssertTrue(vm.isValidForm)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.showAlert)
    }

    func testValidateAmountRejectsNonDecimal() {
        let vm = SendFormFixture.make()
        vm.validateAmount("not-a-number")
        XCTAssertFalse(vm.isValidForm)
        XCTAssertEqual(vm.errorTitle, "error")
        XCTAssertEqual(vm.errorMessage, "decimalAmountError".localized)
        XCTAssertTrue(vm.showAlert)
    }

    func testValidateAmountClearsPriorError() {
        let vm = SendFormFixture.make()
        vm.validateAmount("garbage")
        vm.validateAmount("1.0")
        XCTAssertTrue(vm.isValidForm)
        XCTAssertEqual(vm.errorTitle, "")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - showLoader

    func testShowLoaderMirrorsIsValidatingForm() {
        let vm = SendFormFixture.make()
        XCTAssertFalse(vm.showLoader)
        vm.isValidatingForm = true
        XCTAssertTrue(vm.showLoader)
        vm.isValidatingForm = false
        XCTAssertFalse(vm.showLoader)
    }

    // MARK: - continueButtonDisabled gating

    func testContinueButtonDisabledWhenLoading() {
        let vm = SendFormFixture.make()
        vm.isLoading = true
        XCTAssertTrue(vm.continueButtonDisabled)
    }

    func testContinueButtonDisabledWhenValidating() {
        let vm = SendFormFixture.make()
        vm.isValidatingForm = true
        XCTAssertTrue(vm.continueButtonDisabled)
    }

    func testContinueButtonEnabledWhenIdle() {
        let vm = SendFormFixture.make()
        XCTAssertFalse(vm.continueButtonDisabled)
    }
}
