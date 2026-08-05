//
//  SendVerifyPlanErrorTests.swift
//  VultisigAppTests
//
//  The Verify screen's fee LOAD and its Sign path both reach the same UTXO
//  builder, so they must speak the same language. The load path used to raise
//  whatever the interactor threw, while only the Sign path ran the mapper; and
//  a WalletCore plan that failed reported `fee == 0`, which the load path
//  quoted as a free transaction instead of a failure.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendVerifyPlanErrorTests: XCTestCase {

    // MARK: - Verify load surfaces the planner's reason

    func testLoadSurfacesTheMappedPlannerVerdictForUTXO() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: true) }
        interactor.calculatePlanFeeStub = { _, _ in throw UTXOTransactionPlanError.dustAmount }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()

        XCTAssertTrue(vm.showAlert, "a planner verdict must not load silently")
        XCTAssertEqual(vm.errorMessage, UTXOTransactionPlanError.dustAmount.errorDescription,
                       "the load path must present the planner's own reason")
        XCTAssertFalse(vm.isCalculatingFee)
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadSurfacesTypedUTXOSelectionErrors() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        interactor.calculatePlanFeeStub = { _, _ in throw KeysignPayloadFactory.Errors.utxoTooSmallError }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()

        XCTAssertTrue(vm.showAlert)
        XCTAssertEqual(vm.errorMessage, NSLocalizedString("utxoTooSmallError", comment: ""))
    }

    /// A superseded load pass must stay a cancellation: wrapping it into a
    /// `HelperError` would trip the alert on a screen that is tearing down.
    func testLoadKeepsCancellationQuiet() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        interactor.calculatePlanFeeStub = { _, _ in throw CancellationError() }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()

        // Every flag below reads the same on a load that simply succeeded, so
        // pin that the cancelling call was made at all.
        XCTAssertEqual(interactor.calculatePlanFeeCalls.count, 1)
        XCTAssertFalse(vm.showAlert, "a cancelled load must not raise an alert")
        XCTAssertEqual(vm.errorMessage, "")
        XCTAssertFalse(vm.isCalculatingFee)
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadStillSucceedsWhenThePlanIsFine() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        interactor.calculatePlanFeeStub = { _, _ in BigInt(3_000) }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()

        XCTAssertFalse(vm.showAlert)
        XCTAssertEqual(vm.transaction.fee, BigInt(3_000))
    }

    // MARK: - A failed load must hold Sign

    /// The summary still shows whatever Details handed over — for a max send
    /// after a failed refine, the optimistic full balance at a zero fee — while
    /// Sign would build and sign a fresh plan from live data. Ticking the
    /// consent boxes must not be enough to get there.
    func testFailedLoadKeepsSignDisabledEvenAfterBothChecksAreTicked() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: true) }
        interactor.calculateMaxSendPlanStub = { _, _ in throw URLError(.timedOut) }

        // A max send: the load branches on `tx.sendMaxAmount`, so a non-max
        // fixture would take the flat-fee path and never reach the refinement
        // this test is about.
        let transaction = makeUTXOTransaction().copy(amount: "1", sendMaxAmount: true)
        let vm = SendCryptoVerifyViewModel(transaction: transaction, interactor: interactor)
        await vm.loadGasInfoForSending()

        XCTAssertEqual(interactor.calculateMaxSendPlanCalls.count, 1,
                       "the failure under test is the max-send refinement")
        XCTAssertTrue(interactor.calculatePlanFeeCalls.isEmpty,
                      "a max send takes its fee off the plan, never the flat-fee path")
        XCTAssertTrue(vm.hasLoadError)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        XCTAssertTrue(vm.signButtonDisabled,
                      "Sign must stay disabled while the displayed figures were never resolved")
    }

    func testASuccessfulReloadClearsTheLoadErrorAndReenablesSign() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        var shouldFail = true
        interactor.calculatePlanFeeStub = { _, _ in
            if shouldFail { throw URLError(.timedOut) }
            return BigInt(3_000)
        }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()
        XCTAssertTrue(vm.hasLoadError)

        shouldFail = false
        await vm.loadGasInfoForSending()

        XCTAssertFalse(vm.hasLoadError, "a retry that succeeds must release the hold")
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertFalse(vm.signButtonDisabled)
    }

    /// Clearing the hold on load *entry* would let a cancelled retry release it
    /// while the previous failure's figures are still on screen and nothing has
    /// re-resolved them.
    func testACancelledRetryDoesNotReleaseAnExistingHold() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        var failure: Error = URLError(.timedOut)
        interactor.calculatePlanFeeStub = { _, _ in throw failure }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()
        XCTAssertTrue(vm.hasLoadError)

        // The retry is superseded before it resolves anything.
        failure = CancellationError()
        await vm.loadGasInfoForSending()

        XCTAssertEqual(interactor.calculatePlanFeeCalls.count, 2,
                       "the retry must have run, or the hold was never given a chance to release")
        XCTAssertTrue(vm.hasLoadError,
                      "only a load that runs to completion may release the hold")
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertTrue(vm.signButtonDisabled)
    }

    func testCancelledLoadDoesNotHoldSign() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        interactor.calculatePlanFeeStub = { _, _ in throw CancellationError() }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()

        // `hasLoadError` starts false, so without this the assertion below would
        // also hold for a load that never reached the cancelling call.
        XCTAssertEqual(interactor.calculatePlanFeeCalls.count, 1)
        XCTAssertFalse(vm.hasLoadError,
                       "a superseded load is not a failure — the newer pass owns the outcome")
    }

    // MARK: - Sign path

    func testSignPathSurfacesTheMappedPlannerVerdict() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        interactor.buildKeysignPayloadStub = { _ in throw UTXOTransactionPlanError.insufficientFunds }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        do {
            _ = try await vm.validateForm()
            XCTFail("a failed plan must not produce a signable payload")
        } catch {
            XCTAssertEqual((error as? HelperError)?.errorDescription,
                           UTXOTransactionPlanError.insufficientFunds.errorDescription)
        }
    }

    /// The sign path must follow the same convention as the destination guards
    /// beside it: a cancelled build aborts quietly instead of raising an alert.
    func testSignPathPropagatesCancellation() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in throw CancellationError() }

        let vm = SendCryptoVerifyViewModel(transaction: makeUTXOTransaction(), interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        do {
            _ = try await vm.validateForm()
            XCTFail("expected the cancellation to propagate")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("cancellation must not be rewrapped, got \(error)")
        }
    }

    // MARK: - The shared mapper

    func testSendFailureMapsTypedFactoryErrors() {
        XCTAssertEqual(
            SendCryptoVerifyLogic.sendFailure(KeysignPayloadFactory.Errors.notEnoughUTXOError).errorDescription,
            NSLocalizedString("notEnoughUTXOError", comment: "")
        )
        XCTAssertEqual(
            SendCryptoVerifyLogic.sendFailure(KeysignPayloadFactory.Errors.notEnoughBalanceError).errorDescription,
            NSLocalizedString("notEnoughBalanceError", comment: "")
        )
    }

    func testSendFailureCarriesPlannerVerdictsThrough() {
        XCTAssertEqual(
            SendCryptoVerifyLogic.sendFailure(UTXOTransactionPlanError.transactionTooLarge).errorDescription,
            UTXOTransactionPlanError.transactionTooLarge.errorDescription
        )
    }

    // MARK: - Fixture

    private func makeUTXOTransaction() -> SendTransaction {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        return SendTransaction(
            coin: btc,
            vault: SendFormFixture.makeVault(),
            fromAddress: btc.address,
            toAddress: "bc1qtest",
            toAddressLabel: nil,
            amount: "0.5",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: btc
        )
    }
}
