//
//  SendMaxAmountStickinessTests.swift
//  VultisigAppTests
//
//  Two inverse properties of the Send amount fields, both of which have to hold
//  at once.
//
//  1. A *superseded* keystroke commit must never clear `sendMaxAmount`. Typing
//     into an amount field debounces the conversion, so a commit armed by
//     typing can otherwise land after a Max/percentage preset, a QR fill or a
//     coin switch has already replaced the amount. Applying it clears
//     `sendMaxAmount` while the amount stays at the full balance — the state
//     that makes WalletCore's exact coin selector try to fund `balance + fee`
//     out of `balance`, fail, and surface as the generic "insufficient UTXOs
//     available" on a healthy wallet.
//
//  2. A *genuine* keystroke must clear `sendMaxAmount` immediately, not when
//     its commit fires half a second later. Continue does not wait for a
//     pending commit, so otherwise `makeTransaction` snapshots a hand-typed
//     amount still flagged as a max send and the UTXO signer sweeps the wallet.
//
//  Property 1 is guaranteed by *cancellation*, not by filtering: the form owns
//  the debouncer (`SendDetailsViewModel.amountCommitTask`), so every path that
//  writes the amount itself cancels the pending commit before writing. These
//  tests hold on to the armed task, let the newer write happen, then await that
//  task — giving the superseded commit every chance to run — and assert it was
//  cancelled and changed nothing.
//
//  Value comparison could not substitute for cancellation: typing the full
//  balance and then tapping Max produces the *same string* from two different
//  intents (`testASupersededCommitCarryingTheFullBalanceCannotClearTheIntent`).
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendMaxAmountStickinessTests: XCTestCase {

    // MARK: - Helpers

    /// Mirror the crypto field's binding: write the source of truth, then report
    /// the keystroke. Returns the commit it armed so the test can await it.
    private func typeAmount(_ value: String, into vm: SendDetailsViewModel) -> Task<Void, Never>? {
        vm.amount = value
        vm.onAmountFieldEdited(value)
        return vm.amountCommitTask
    }

    /// Same, for the fiat field.
    private func typeFiat(_ value: String, into vm: SendDetailsViewModel) -> Task<Void, Never>? {
        vm.amountInFiat = value
        vm.onFiatAmountFieldEdited(value)
        return vm.amountCommitTask
    }

    /// Give a commit every chance to run, then report whether it was cancelled
    /// instead. Awaiting a cancelled commit returns as soon as its sleep throws,
    /// so this is the "the debounce window elapsed and nothing ran" assertion
    /// without a wall-clock wait.
    private func settle(_ commit: Task<Void, Never>?) async -> Bool {
        await commit?.value
        return commit?.isCancelled ?? false
    }

    // MARK: - Property 1: a superseded commit cannot clear the max intent

    /// The case value equality cannot catch: the superseded keystroke and the
    /// Max preset produce the *same* string, so nothing about the value can tell
    /// the two intents apart — only the fact that the commit was cancelled.
    /// Getting this wrong reproduces the reported bug exactly: the flag clears
    /// while the amount sits at the full balance.
    func testASupersededCommitCarryingTheFullBalanceCannotClearTheIntent() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000") // 1 BTC
        let vm = SendFormFixture.make(coin: btc)

        // The user types the full balance, then taps Max before the commit fires.
        let superseded = typeAmount("1", into: vm)
        XCTAssertNotNil(superseded, "precondition: the keystroke armed a commit")

        vm.setMaxAmount(percentage: 100)
        XCTAssertEqual(vm.amount, "1", "precondition: the optimistic Max fill equals the typed value")

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled, "tapping Max must cancel the pending keystroke commit, not leave it to be filtered")
        XCTAssertTrue(vm.sendMaxAmount, "a superseded commit must not clear the max-send intent")

        await vm.feeRefineTask?.value
    }

    /// The dangerous shape from the report: an empty/unpriceable stale value.
    /// Applying it would clear the flag *without* restoring the amount.
    func testASupersededEmptyCommitAfterMaxKeepsIntentAndAmount() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("", into: vm)
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        let maxAmount = vm.amount

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled)
        XCTAssertTrue(vm.sendMaxAmount, "a superseded commit must not clear the max-send intent")
        XCTAssertEqual(vm.amount, maxAmount, "a superseded commit must not touch the amount")
    }

    func testASupersededTypedCommitAfterMaxKeepsIntentAndAmount() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("0.5", into: vm)
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        let maxAmount = vm.amount

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled)
        XCTAssertTrue(vm.sendMaxAmount)
        XCTAssertEqual(vm.amount, maxAmount,
                       "a superseded commit must not restore the previously typed amount")
    }

    /// A cancelled commit is ordinary control flow — the debounce's sleep throws
    /// and the commit is simply skipped. Nothing may surface to the user.
    func testACancelledCommitIsQuiet() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("0.5", into: vm)
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        let maxAmount = vm.amount

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled, "precondition: the commit was superseded, not applied")
        XCTAssertTrue(vm.sendMaxAmount)
        XCTAssertEqual(vm.amount, maxAmount)

        XCTAssertFalse(vm.showAlert, "a superseded debounce is not an error")
        XCTAssertFalse(vm.showAmountAlert)
    }

    func testMaxThenASupersededCommitStillHandsOffAMaxTransaction() async throws {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)
        vm.toAddress = "bc1qtest"

        let superseded = typeAmount("", into: vm)
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        _ = await settle(superseded)

        let tx = try vm.makeTransaction()
        XCTAssertTrue(tx.sendMaxAmount,
                      "the hand-off transaction must still carry the max-send flag, or the UTXO signer plans an exact-amount spend of the full balance")
    }

    // MARK: - Property 2: a genuine edit clears the max intent immediately

    /// Continue does not wait for a pending commit. If the intent only lapsed
    /// when the commit ran, a fast Continue after typing would snapshot a
    /// hand-typed amount still marked as a max send — and the UTXO signer would
    /// sweep the wallet for someone who asked to send a specific figure.
    func testTypingClearsTheMaxIntentBeforeContinueCanSnapshotIt() async throws {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)
        vm.toAddress = "bc1qtest"

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        XCTAssertTrue(vm.sendMaxAmount)

        // The user types, then taps Continue before the commit fires. Nothing
        // below suspends, so the commit provably has not run yet.
        let pending = typeAmount("0.25", into: vm)
        XCTAssertEqual(pending?.isCancelled, false, "precondition: the commit is still pending")

        XCTAssertFalse(vm.sendMaxAmount, "a keystroke must drop the max intent synchronously")

        let tx = try vm.makeTransaction()
        XCTAssertFalse(tx.sendMaxAmount, "the hand-off must not sign a max send for a hand-typed amount")
        XCTAssertEqual(tx.amount, "0.25")

        _ = await settle(pending)
    }

    func testTypingInTheFiatFieldAlsoClearsTheIntentImmediately() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        let pending = typeFiat("250", into: vm)
        XCTAssertEqual(pending?.isCancelled, false, "precondition: the commit is still pending")
        XCTAssertFalse(vm.sendMaxAmount, "the fiat field has the same window")

        _ = await settle(pending)
    }

    /// Both properties at once: a genuine edit clears the intent, and its
    /// commit — superseded by a later Max — still cannot clear it back.
    func testBothPropertiesHoldTogether() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("0.25", into: vm)
        XCTAssertFalse(vm.sendMaxAmount, "property 2: the keystroke dropped the intent synchronously")

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        let maxAmount = vm.amount
        XCTAssertTrue(vm.sendMaxAmount)

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled, "property 1: the superseded commit was cancelled")
        XCTAssertTrue(vm.sendMaxAmount)
        XCTAssertEqual(vm.amount, maxAmount)
    }

    // MARK: - A commit that is *not* superseded still applies

    func testACommittedEditClearsTheIntentAndConverts() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        XCTAssertTrue(vm.sendMaxAmount)

        let commit = typeAmount("0.25", into: vm)
        await commit?.value

        XCTAssertEqual(commit?.isCancelled, false, "nothing superseded this commit, so it must have run")
        XCTAssertNil(vm.amountCommitTask, "a commit that ran must have released the pending slot")
        XCTAssertFalse(vm.sendMaxAmount, "a live edit is an explicit amount choice")
        XCTAssertEqual(vm.amount, "0.25")
    }

    func testClearingTheAmountFieldClearsTheIntent() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        let commit = typeAmount("", into: vm)
        await commit?.value

        XCTAssertFalse(vm.sendMaxAmount,
                       "clearing the field is an explicit amount choice, not a superseded commit")
    }

    // MARK: - Fiat field

    func testASupersededFiatCommitAfterMaxKeepsIntentAndAmount() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeFiat("1234", into: vm)
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        let maxAmount = vm.amount

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled)
        XCTAssertTrue(vm.sendMaxAmount,
                      "a superseded fiat-field commit must not clear the max-send intent")
        XCTAssertEqual(vm.amount, maxAmount)
    }

    func testACommittedFiatEditClearsIntentAndAmount() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // Clearing the fiat field: `fiatToCoinAmount` returns nil, so the coin
        // amount is wiped. The intent must go with it — "send everything" paired
        // with an empty amount field is not a state the form should carry.
        let commit = typeFiat("", into: vm)
        await commit?.value

        XCTAssertEqual(vm.amount, "")
        XCTAssertFalse(vm.sendMaxAmount,
                       "wiping the amount via the fiat field must also drop the max-send intent")
    }

    /// The two fields share one pending slot, so arming from either cancels the
    /// other: an in-flight commit from the field the user just left cannot
    /// clobber the field they moved to.
    func testMovingToTheFiatFieldCancelsTheCryptoFieldsPendingCommit() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let cryptoCommit = typeAmount("0.4", into: vm)

        // The user switches to the fiat field and types before the crypto
        // commit fires.
        let fiatCommit = typeFiat("250", into: vm)

        let cryptoWasCancelled = await settle(cryptoCommit)
        XCTAssertTrue(cryptoWasCancelled, "arming the fiat field must cancel the field the user left")
        XCTAssertEqual(vm.amountInFiat, "250",
                       "a superseded crypto commit must not overwrite the newer fiat input")

        // Cancelling the older commit must not have taken the newer one with it:
        // the fiat commit still applies (with no rate available it wipes the coin
        // amount, which is what proves it ran).
        await fiatCommit?.value
        XCTAssertEqual(fiatCommit?.isCancelled, false)
        XCTAssertEqual(vm.amount, "",
                       "the newer fiat commit must still run after an older one was cancelled")
    }

    // MARK: - Every other writer of the amount cancels the pending commit

    /// `SendDetailsAddressFields.handle(addressResult:)` writes the scanned
    /// amount and converts. A payload-supplied amount is an explicit amount, so
    /// it drops the max intent...
    func testAQRAmountFillClearsTheIntent() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        vm.amount = "0.01"
        vm.convertToFiat(newValue: "0.01")

        XCTAssertFalse(vm.sendMaxAmount)
        XCTAssertEqual(vm.amount, "0.01")
    }

    /// ...and, like every other writer of the amount, it cancels a keystroke
    /// commit that would otherwise land on top of the value it just wrote.
    func testAQRAmountFillCancelsThePendingCommit() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("0.4", into: vm)

        vm.amount = "0.01"
        vm.convertToFiat(newValue: "0.01")

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(vm.amount, "0.01", "a superseded commit must not undo a QR fill")
    }

    /// `SendDetailsAmountTextField`'s `.onChange(of: viewModel.coin)` — the
    /// amount now describes a different asset, so the max intent lapses.
    func testACoinSwitchClearsTheIntent() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        vm.coin = SendFormFixture.makeETH()
        vm.convertToFiat(newValue: vm.amount)

        XCTAssertFalse(vm.sendMaxAmount)
    }

    func testACoinSwitchCancelsThePendingCommit() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("0.4", into: vm)

        vm.coin = SendFormFixture.makeETH()
        vm.convertToFiat(newValue: vm.amount)

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled)
    }

    func testAResetCancelsThePendingCommit() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("0.3", into: vm)
        vm.reset(to: SendFormFixture.makeBTC(rawBalance: "100000000"))

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(vm.amount, "", "a commit from before the reset must not repopulate the form")
    }

    func testAHydrateCancelsThePendingCommit() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("0.3", into: vm)
        vm.hydrate(from: SendDetailsSeed(
            coin: btc,
            vault: SendFormFixture.makeVault(),
            hasPreselectedCoin: true,
            fromAddress: btc.address,
            toAddress: "bc1qtest",
            toAddressLabel: nil,
            lastResolvedAddress: nil,
            amount: "0.75",
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
            wasmContractPayload: nil
        ))

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(vm.amount, "0.75", "a commit from before the hydrate must not overwrite the seed")
        XCTAssertTrue(vm.sendMaxAmount, "nor clear the intent the seed restored")
    }

    // MARK: - Percentage presets

    func testAPartialPresetCancelsThePendingCommit() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        let superseded = typeAmount("0.9", into: vm)
        vm.setMaxAmount(percentage: 50)
        let presetAmount = vm.amount

        let wasCancelled = await settle(superseded)
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(vm.amount, presetAmount,
                       "a superseded commit must not overwrite a percentage preset either")
        XCTAssertFalse(vm.sendMaxAmount, "a partial preset never sets the max-send intent")
    }

    // MARK: - Background fee refine

    /// The refine has no edit token to consult any more. It stands down on
    /// `sendMaxAmount`, which a keystroke clears synchronously — so a refine
    /// settling after the user starts typing cannot overwrite their input, and
    /// their commit still lands afterwards.
    func testTheFeeRefineStandsDownWhenTheUserTypesWhileItIsInFlight() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)

        // The user starts typing before the refine settles.
        let commit = typeAmount("0.3", into: vm)

        await vm.feeRefineTask?.value

        XCTAssertEqual(vm.amount, "0.3",
                       "a settling max-fee refine must not overwrite a newer keystroke")

        // And that keystroke's own commit is still accepted afterwards.
        await commit?.value
        XCTAssertEqual(commit?.isCancelled, false,
                       "the refine standing down must not have cancelled the user's commit")
        XCTAssertFalse(vm.sendMaxAmount)
        XCTAssertEqual(vm.amount, "0.3")
    }

    func testTheFeeRefineStillSettlesWhenNothingElseTouchesTheField() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000") // 1 BTC
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // The mock plans `balance − 3_000` by default: 99_997_000 sats.
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(),
                       Decimal(string: "0.99997"),
                       "the guards must not block the refine on an untouched field")
        XCTAssertTrue(vm.sendMaxAmount)
    }
}
