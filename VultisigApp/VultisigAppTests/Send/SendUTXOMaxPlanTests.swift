//
//  SendUTXOMaxPlanTests.swift
//  VultisigAppTests
//
//  UTXO Max must come from a real `useMaxAmount` WalletCore plan.
//
//  A UTXO fee is `rate × size` and the size only exists once inputs are
//  selected, so the sat/vB rate carried on `BlockChainSpecific` is not a fee.
//  Refining Max with it produced `balance − ~12 sats` — reserving roughly a
//  dozen sats for a fee of a few thousand — and the Details figure disagreed
//  with the one Verify would confirm.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendUTXOMaxPlanTests: XCTestCase {

    // MARK: - The plan drives the amount and the fee

    func testMaxSettlesToThePlannedAmountAndFee() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000") // 1 BTC
        let interactor = MockSendInteractor()
        interactor.calculateMaxSendPlanStub = { _, _ in
            SendMaxPlanResult(amount: BigInt(99_996_780), fee: BigInt(3_220), byteFee: BigInt(28))
        }
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(),
                       Decimal(string: "0.9999678"))
        XCTAssertEqual(vm.fee, BigInt(3_220))
        XCTAssertEqual(vm.gas, BigInt(28))
        XCTAssertTrue(vm.sendMaxAmount)
    }

    /// The planned amount is `Σ selected inputs − fee`, which can be less than
    /// `balance − fee` when the spendability filter excluded an output. The
    /// planner's figure is the honest one and must win.
    func testPlannedAmountWinsOverBalanceMinusFee() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000") // 1 BTC
        let interactor = MockSendInteractor()
        interactor.calculateMaxSendPlanStub = { _, _ in
            // Only 0.6 BTC of the balance was spendable.
            SendMaxPlanResult(amount: BigInt(59_997_000), fee: BigInt(3_000), byteFee: BigInt(20))
        }
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(),
                       Decimal(string: "0.59997"),
                       "the displayed max must be what the planner will actually send")
    }

    // MARK: - Request contents

    func testMaxPlanRequestAsksForAMaxSendWithTheFormsFeeInputs() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)
        vm.toAddress = "bc1qrecipient"
        vm.feeMode = .safeLow
        vm.customByteFee = BigInt(4)
        vm.memo = "hello"

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        let request = interactor.calculateMaxSendPlanCalls.last
        XCTAssertEqual(request?.sendMaxAmount, true,
                       "the plan must be a max-send plan, or the fee describes a different transaction")
        XCTAssertEqual(request?.toAddress, "bc1qrecipient",
                       "the recipient's script type sizes the output, and the size is the fee")
        XCTAssertEqual(request?.feeMode, .safeLow)
        XCTAssertEqual(request?.customByteFee, BigInt(4))
        XCTAssertEqual(request?.memo, "hello")
        XCTAssertEqual(request?.amount, BigInt(100_000_000),
                       "the planner is handed the whole balance; it derives the output from the inputs")
    }

    func testMaxPlanFallsBackToOwnAddressWithNoRecipientYet() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertEqual(interactor.calculateMaxSendPlanCalls.last?.toAddress, btc.address)
    }

    // MARK: - Failure handling

    /// A planner verdict will not resolve itself on retry. Surface it inline,
    /// while the amount is still editable, instead of letting it reappear at
    /// Verify as a generic "insufficient UTXOs".
    func testPlannerVerdictSurfacesInlineOnTheAmountField() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "5000")
        let interactor = MockSendInteractor()
        interactor.calculateMaxSendPlanStub = { _, _ in throw UTXOTransactionPlanError.dustAmount }
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertTrue(vm.showAmountAlert)
        XCTAssertEqual(vm.errorMessage, UTXOTransactionPlanError.dustAmount.errorDescription)
        XCTAssertFalse(vm.isCalculatingFee)
    }

    func testUtxoSelectionVerdictAlsoSurfacesInline() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "5000")
        let interactor = MockSendInteractor()
        interactor.calculateMaxSendPlanStub = { _, _ in throw KeysignPayloadFactory.Errors.utxoTooSmallError }
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertTrue(vm.showAmountAlert)
        XCTAssertEqual(vm.errorMessage, NSLocalizedString("utxoTooSmallError", comment: ""))
    }

    /// A transport failure is temporary and Verify recomputes before signing —
    /// it must not wipe the field or paint an error the user can't act on.
    func testTransportFailureKeepsTheOptimisticFillAndStaysQuiet() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let interactor = MockSendInteractor()
        interactor.calculateMaxSendPlanStub = { _, _ in throw URLError(.timedOut) }
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertEqual(interactor.calculateMaxSendPlanCalls.count, 1,
                       "the fill below is the optimistic one only if a plan was actually attempted")
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "1"),
                       "a flaky lookup must keep the optimistic full-balance fill")
        XCTAssertFalse(vm.showAmountAlert)
        XCTAssertTrue(vm.sendMaxAmount)
        XCTAssertFalse(vm.isCalculatingFee)
    }

    func testANewPresetClearsAPreviousPlannerVerdict() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "5000")
        let interactor = MockSendInteractor()
        interactor.calculateMaxSendPlanStub = { _, _ in throw UTXOTransactionPlanError.dustAmount }
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        XCTAssertTrue(vm.showAmountAlert)

        vm.setMaxAmount(percentage: 50)

        XCTAssertFalse(vm.showAmountAlert, "each attempt states its own outcome")
    }

    // MARK: - Guards still hold

    func testASupersededPlanDoesNotWrite() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let interactor = MockSendInteractor()
        interactor.calculateMaxSendPlanStub = { _, _ in
            SendMaxPlanResult(amount: BigInt(99_997_000), fee: BigInt(3_000), byteFee: BigInt(20))
        }
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        // The user types before the plan settles. The keystroke drops the
        // max-send intent synchronously, which is what stands the plan down.
        vm.amount = "0.2"
        vm.onAmountFieldEdited("0.2")

        await vm.feeRefineTask?.value

        XCTAssertEqual(interactor.calculateMaxSendPlanCalls.count, 1,
                       "the plan must have resolved, or there was nothing to stand down")
        XCTAssertEqual(vm.amount, "0.2", "a superseded plan must not overwrite a newer keystroke")
    }

    func testNonUTXOChainsKeepTheFlatFeePath() async {
        let atom = SendFormFixture.makeATOM(rawBalance: "10000000") // 10 ATOM
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .Cosmos(accountNumber: 0, sequence: 0, gas: 2_000, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
        }
        let vm = SendFormFixture.make(coin: atom, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertTrue(interactor.calculateMaxSendPlanCalls.isEmpty,
                      "only the UTXO family plans; every other chain quotes a flat fee")
        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 1)
        XCTAssertEqual(interactor.fetchChainSpecificCalls.last?.amount, .zero,
                       "the flat-fee estimate keeps passing zero so an EVM gas estimate isn't simulated against the whole balance")
    }

    // MARK: - Verify confirms the plan it will sign

    /// A UTXO max send signs `Σ selected inputs − fee`. Verify used to re-derive
    /// `balance − fee`, which is a different number whenever the selection left
    /// an output out — so the summary could promise the recipient more than the
    /// signed transaction delivers.
    func testVerifyShowsThePlannedAmountRatherThanBalanceMinusFee() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(20), sendMaxAmount: true) }
        interactor.calculateMaxSendPlanStub = { _, _ in
            // Only 0.6 BTC was spendable, so `balance − fee` would overstate it.
            SendMaxPlanResult(amount: BigInt(59_997_000), fee: BigInt(3_000), byteFee: BigInt(20))
        }

        let vm = SendCryptoVerifyViewModel(transaction: makeMaxUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.amount.replacingOccurrences(of: ",", with: ".").toDecimal(),
                       Decimal(string: "0.59997"),
                       "Verify must confirm the amount the planner will actually send")
        XCTAssertEqual(vm.transaction.fee, BigInt(3_000))
        XCTAssertTrue(interactor.calculatePlanFeeCalls.isEmpty,
                      "a max send reads its amount and fee off one plan, not two")
    }

    /// The plan Verify confirms is about to be signed, so it must be built from
    /// a freshly fetched UTXO set — matching what `calculatePlanFee` did.
    func testVerifyRefreshesTheUtxoSetBeforePlanning() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(20), sendMaxAmount: true) }

        let vm = SendCryptoVerifyViewModel(transaction: makeMaxUTXOTransaction(), interactor: interactor)
        await vm.loadGasInfoForSending()

        XCTAssertEqual(interactor.calculateMaxSendPlanRefreshFlags, [true])
    }

    func testDetailsPlansAgainstTheCachedUtxoSet() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        XCTAssertEqual(interactor.calculateMaxSendPlanRefreshFlags, [false],
                       "Max is tapped repeatedly while editing; only the plan that gets signed refreshes")
    }

    func testVerifyKeepsTheFlatFeePathForANonMaxUTXOSend() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(20), sendMaxAmount: false) }
        interactor.calculatePlanFeeStub = { _, _ in BigInt(2_500) }

        var tx = makeMaxUTXOTransaction()
        tx = tx.copy(amount: "0.25", sendMaxAmount: false)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        await vm.loadGasInfoForSending()

        XCTAssertTrue(interactor.calculateMaxSendPlanCalls.isEmpty)
        XCTAssertEqual(vm.transaction.fee, BigInt(2_500))
        XCTAssertEqual(vm.transaction.amount, "0.25", "a non-max send keeps the amount the user chose")
    }

    // MARK: - Sign must build the plan Verify displayed

    /// `validateUtxosIfNeeded` refetches the input set moments before the
    /// payload is built, and a `useMaxAmount` plan is defined by whatever that
    /// set contains. If it moved since Verify planned what it displayed, the
    /// ceremony must not sign the difference silently.
    func testSignRefusesWhenThePlannedOutcomeNoLongerMatchesTheDisplayedOne() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(20), sendMaxAmount: true) }
        // Verify displayed 0.99997 / 3_000; an output confirmed in between, so
        // the build-time plan now sweeps more.
        interactor.plannedOutcomeStub = { _ in
            SendMaxPlanResult(amount: BigInt(149_996_200), fee: BigInt(3_800), byteFee: BigInt(20))
        }

        let vm = SendCryptoVerifyViewModel(transaction: makeMaxUTXOTransaction(), interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        do {
            _ = try await vm.validateForm()
            XCTFail("signing must not proceed on a plan the user was never shown")
        } catch {
            XCTAssertEqual((error as? HelperError)?.errorDescription,
                           NSLocalizedString("maxSendPlanChangedError", comment: ""))
        }
    }

    func testSignProceedsWhenThePlanStillMatches() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(20), sendMaxAmount: true) }
        interactor.plannedOutcomeStub = { _ in
            SendMaxPlanResult(amount: BigInt(99_997_000), fee: BigInt(3_000), byteFee: BigInt(20))
        }

        var tx = makeMaxUTXOTransaction()
        tx = tx.copy(fee: BigInt(3_000))
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try? await vm.validateForm()
        XCTAssertNotNil(payload, "an unchanged plan must sign normally")
        XCTAssertEqual(interactor.plannedOutcomeCalls.count, 1)
    }

    /// The guard compares the planner's raw figure against the amount string the
    /// form carries, so that round-trip has to be exact or every max send would
    /// be blocked.
    func testFormattedMaxAmountRoundTripsExactly() {
        let btc = SendFormFixture.makeBTC()
        for raw in [BigInt(99_997_000), BigInt(1), BigInt(12_345_678), BigInt(100_000_000), BigInt(59_997_000)] {
            let formatted = SendCryptoLogic.formatRawAmount(raw, coin: btc)
            XCTAssertEqual(SendCryptoLogic.amountInRaw(coin: btc, amount: formatted), raw,
                           "\(raw) must survive format → parse unchanged")
        }
    }

    func testNonMaxSendsAreNotGatedByThePlanCheck() async {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(20), sendMaxAmount: false) }
        interactor.calculatePlanFeeStub = { _, _ in BigInt(2_500) }
        interactor.plannedOutcomeStub = { _ in
            XCTFail("a non-max send pins its recipient amount; it must not be gated")
            return nil
        }

        var tx = makeMaxUTXOTransaction()
        tx = tx.copy(amount: "0.25", sendMaxAmount: false)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        _ = try? await vm.validateForm()
        XCTAssertEqual(interactor.buildKeysignPayloadCalls.count, 1,
                       "the build must have reached the point the gate sits at, or nothing was skipped")
        XCTAssertTrue(interactor.plannedOutcomeCalls.isEmpty)
    }

    private func makeMaxUTXOTransaction() -> SendTransaction {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        return SendTransaction(
            coin: btc,
            vault: SendFormFixture.makeVault(),
            fromAddress: btc.address,
            toAddress: "bc1qtest",
            toAddressLabel: nil,
            amount: "0.99997",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: true,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: btc
        )
    }

    // MARK: - Raw-amount formatting

    func testFormatRawAmountTruncatesToTheCoinsPrecision() {
        let btc = SendFormFixture.makeBTC()
        XCTAssertEqual(SendCryptoLogic.formatRawAmount(BigInt(99_995_000), coin: btc)
            .replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "0.99995"))
        XCTAssertEqual(SendCryptoLogic.formatRawAmount(BigInt(1), coin: btc)
            .replacingOccurrences(of: ",", with: ".").toDecimal(), Decimal(string: "0.00000001"))
    }

    func testFormatRawAmountClampsNonPositiveToZero() {
        let btc = SendFormFixture.makeBTC()
        XCTAssertEqual(SendCryptoLogic.formatRawAmount(BigInt(-1), coin: btc)
            .replacingOccurrences(of: ",", with: ".").toDecimal(), .zero)
        XCTAssertEqual(SendCryptoLogic.formatRawAmount(.zero, coin: btc)
            .replacingOccurrences(of: ",", with: ".").toDecimal(), .zero)
    }
}
