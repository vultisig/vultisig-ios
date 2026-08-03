//
//  SendMaxAmountStickinessTests.swift
//  VultisigAppTests
//
//  `sendMaxAmount` must survive every event that is not the user choosing an
//  explicit amount.
//
//  The Send amount fields debounce through the process-wide
//  `DebounceHelper.shared`, which holds a single pending work item. A callback
//  armed by typing can therefore land *after* a Max/percentage preset, a QR
//  fill or a coin switch has already replaced the amount. Applying such a
//  superseded callback used to clear `sendMaxAmount` while the amount stayed at
//  the full balance — the state that makes WalletCore's exact coin selector try
//  to fund `balance + fee` out of `balance`, fail, and surface as the generic
//  "insufficient UTXOs available".
//
//  The fields mint a token via `beginAmountEdit()` synchronously on each
//  keystroke and present it back when the debounce fires; these tests simulate
//  that by minting a token, letting a newer event land, and then delivering the
//  callback with the older token.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendMaxAmountStickinessTests: XCTestCase {

    // MARK: - Stale crypto-field callbacks (the reported repro)

    func testStaleEmptyAmountCallbackAfterMaxKeepsFlagAndAmount() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000") // 1 BTC
        let vm = SendFormFixture.make(coin: btc)

        // The user cleared the field (arming a debounce carrying ""), then
        // tapped Max before it fired.
        vm.amount = ""
        let staleToken = vm.beginAmountEdit()
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        let maxAmount = vm.amount

        // The stale callback lands now.
        vm.onAmountFieldEdited("", generation: staleToken)

        XCTAssertTrue(vm.sendMaxAmount,
                      "a superseded debounce must not clear the max-send flag")
        XCTAssertEqual(vm.amount, maxAmount,
                       "a superseded debounce must not touch the amount")
    }

    func testStaleTypedAmountCallbackAfterMaxKeepsFlagAndAmount() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.amount = "0.5"
        let staleToken = vm.beginAmountEdit()
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        let maxAmount = vm.amount

        vm.onAmountFieldEdited("0.5", generation: staleToken)

        XCTAssertTrue(vm.sendMaxAmount)
        XCTAssertEqual(vm.amount, maxAmount,
                       "a superseded debounce must not restore the previously typed amount")
    }

    /// The case value equality cannot catch: the stale keystroke and the Max
    /// preset produce the *same* string, so only the edit token can tell the two
    /// intents apart. Getting this wrong reproduces the reported bug exactly —
    /// the flag clears while the amount sits at the full balance.
    func testStaleCallbackCarryingTheFullBalanceAfterMaxKeepsTheFlag() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000") // 1 BTC
        let vm = SendFormFixture.make(coin: btc)

        // The user typed the full balance, then tapped Max before the debounce
        // fired. The optimistic Max fill is the same string. Everything below
        // runs without a suspension point, so it reproduces the exact window
        // before the background fee refine can land.
        vm.amount = "1"
        let staleToken = vm.beginAmountEdit()
        vm.setMaxAmount(percentage: 100)
        XCTAssertEqual(vm.amount, "1", "precondition: the optimistic Max fill equals the typed value")

        vm.onAmountFieldEdited("1", generation: staleToken)

        XCTAssertTrue(vm.sendMaxAmount,
                      "a stale callback whose value coincides with the Max fill must still be dropped")

        await vm.feeRefineTask?.value
    }

    func testMaxThenStaleCallbackStillHandsOffAMaxTransaction() async throws {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)
        vm.toAddress = "bc1qtest"

        vm.amount = ""
        let staleToken = vm.beginAmountEdit()
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        vm.onAmountFieldEdited("", generation: staleToken)

        let tx = try vm.makeTransaction()
        XCTAssertTrue(tx.sendMaxAmount,
                      "the hand-off transaction must still carry the max-send flag, or the UTXO signer plans an exact-amount spend of the full balance")
    }

    // MARK: - Genuine edits still clear the flag

    func testCurrentAmountCallbackClearsTheFlag() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        XCTAssertTrue(vm.sendMaxAmount)

        // The user types an explicit amount; the debounce fires with the token
        // that keystroke minted, and nothing newer has landed since.
        vm.amount = "0.25"
        let token = vm.beginAmountEdit()
        vm.onAmountFieldEdited("0.25", generation: token)

        XCTAssertFalse(vm.sendMaxAmount,
                       "a live edit is an explicit amount choice")
        XCTAssertEqual(vm.amount, "0.25")
    }

    func testClearingTheAmountFieldClearsTheFlag() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        vm.amount = ""
        let token = vm.beginAmountEdit()
        vm.onAmountFieldEdited("", generation: token)

        XCTAssertFalse(vm.sendMaxAmount,
                       "clearing the field is an explicit amount choice, not a stale callback")
    }

    // MARK: - Fiat field

    func testStaleFiatCallbackAfterMaxKeepsFlagAndAmount() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.amountInFiat = "1234"
        let staleToken = vm.beginAmountEdit()
        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value
        let maxAmount = vm.amount

        vm.onFiatAmountFieldEdited("1234", generation: staleToken)

        XCTAssertTrue(vm.sendMaxAmount,
                      "a superseded fiat-field debounce must not clear the max-send flag")
        XCTAssertEqual(vm.amount, maxAmount)
    }

    func testCurrentFiatCallbackClearsFlagAndAmount() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // Clearing the fiat field: `fiatToCoinAmount` returns nil, so the coin
        // amount is wiped. The flag must go with it — "send everything" paired
        // with an empty amount field is not a state the form should carry.
        vm.amountInFiat = ""
        let token = vm.beginAmountEdit()
        vm.onFiatAmountFieldEdited("", generation: token)

        XCTAssertEqual(vm.amount, "")
        XCTAssertFalse(vm.sendMaxAmount,
                       "wiping the amount via the fiat field must also drop the max-send flag")
    }

    /// The two fields share one token sequence, so an in-flight callback from
    /// the field the user just left cannot clobber the field they moved to.
    func testStaleCryptoCallbackDoesNotWinOverANewerFiatEdit() {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.amount = "0.4"
        let cryptoToken = vm.beginAmountEdit()

        // The user switches to the fiat field and types before the crypto
        // callback fires.
        vm.amountInFiat = "250"
        let fiatToken = vm.beginAmountEdit()
        XCTAssertNotEqual(cryptoToken, fiatToken)

        vm.onAmountFieldEdited("0.4", generation: cryptoToken)

        XCTAssertEqual(vm.amountInFiat, "250",
                       "a superseded crypto callback must not overwrite the newer fiat input")

        // Dropping the older callback must not have invalidated the newer one:
        // the fiat commit still applies (with no rate available it wipes the
        // coin amount, which is what proves it ran).
        vm.onFiatAmountFieldEdited("250", generation: fiatToken)
        XCTAssertEqual(vm.amount, "",
                       "the newer fiat callback must still be accepted after an older one was dropped")
    }

    // MARK: - Non-edit callers keep their existing semantics

    func testQRAmountFillClearsTheFlag() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // `SendDetailsAddressFields.handle(addressResult:)` writes the scanned
        // amount and converts. A payload-supplied amount is an explicit amount.
        vm.amount = "0.01"
        vm.convertToFiat(newValue: "0.01")

        XCTAssertFalse(vm.sendMaxAmount)
        XCTAssertEqual(vm.amount, "0.01")
    }

    func testCoinSwitchRefreshClearsTheFlag() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // `SendDetailsAmountTextField`'s `.onChange(of: viewModel.coin)` — the
        // amount now describes a different asset, so the max intent lapses.
        vm.coin = SendFormFixture.makeETH()
        vm.convertToFiat(newValue: vm.amount)

        XCTAssertFalse(vm.sendMaxAmount)
    }

    func testResetSupersedesAnInFlightCallback() {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.amount = "0.3"
        let staleToken = vm.beginAmountEdit()
        vm.reset(to: SendFormFixture.makeBTC(rawBalance: "100000000"))

        vm.onAmountFieldEdited("0.3", generation: staleToken)

        XCTAssertEqual(vm.amount, "", "a callback from before the reset must not repopulate the form")
    }

    // MARK: - Background fee refine

    /// A keystroke does not clear `sendMaxAmount` until its own debounce lands,
    /// so the refine cannot use the flag alone to decide it still owns the
    /// field: it would overwrite the newer input and then bump the token,
    /// invalidating the very callback that was about to honour that input.
    func testFeeRefineStandsDownWhenTheUserTypesWhileItIsInFlight() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)

        // The user starts typing before the refine settles.
        vm.amount = "0.3"
        let token = vm.beginAmountEdit()

        await vm.feeRefineTask?.value

        XCTAssertEqual(vm.amount, "0.3",
                       "a settling max-fee refine must not overwrite a newer keystroke")

        // And that keystroke's own debounce is still accepted afterwards.
        vm.onAmountFieldEdited("0.3", generation: token)
        XCTAssertFalse(vm.sendMaxAmount)
        XCTAssertEqual(vm.amount, "0.3")
    }

    func testFeeRefineStillSettlesWhenNothingElseTouchesTheField() async {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000") // 1 BTC
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)

        vm.setMaxAmount(percentage: 100)
        await vm.feeRefineTask?.value

        // The mock plans `balance − 3_000` by default: 99_997_000 sats.
        XCTAssertEqual(vm.amount.replacingOccurrences(of: ",", with: ".").toDecimal(),
                       Decimal(string: "0.99997"),
                       "the token guard must not block the refine on an untouched field")
        XCTAssertTrue(vm.sendMaxAmount)
    }

    // MARK: - Percentage presets

    func testStaleCallbackAfterPartialPresetDoesNotRestoreTypedAmount() {
        let btc = SendFormFixture.makeBTC(rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: btc)

        vm.amount = "0.9"
        let staleToken = vm.beginAmountEdit()
        vm.setMaxAmount(percentage: 50)
        let presetAmount = vm.amount

        vm.onAmountFieldEdited("0.9", generation: staleToken)

        XCTAssertEqual(vm.amount, presetAmount,
                       "a superseded debounce must not overwrite a percentage preset either")
        XCTAssertFalse(vm.sendMaxAmount, "a partial preset never sets the max-send flag")
    }
}
