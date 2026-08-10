//
//  TCYUnstakeBasisPointsTests.swift
//  VultisigAppTests
//
//  The `tcy-:<bps>` memo asks for a fraction of the staked position in
//  ten-thousandths. The amount used to reach it through a whole percentage —
//  `Int(50.0679) * 100` — which spends 100 of the memo's 10 000 steps and made a
//  request for 1002.73 TCY pay out 1001.37.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TCYUnstakeBasisPointsTests: XCTestCase {

    /// The position from the bug report. 1001.37 × 2 recovers the staked balance
    /// the issue rounds to "2002".
    private let staked = Decimal(string: "2002.74")!

    private func makeTCYCoin() -> Coin {
        Coin(
            asset: TokensStore.tcy,
            address: "thor1fixturetcyvaultaddress00000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    /// Types `amount` into the sheet the way the field does, so the view model is
    /// left in the state the real screen leaves it in.
    ///
    /// The two lines after the assignment are what `AmountTextField` and
    /// `UnstakeTransactionScreen` do between them on every keystroke: derive the
    /// percentage from the typed amount, then let the view model reconsider
    /// whether the position is being closed. Skipping them would leave
    /// `percentageSelected` on its initial 100 and quietly test a MAX withdrawal
    /// instead of a custom one.
    private func type(_ amount: String, into viewModel: UnstakeTransactionViewModel) {
        viewModel.amountField.value = amount
        viewModel.percentageSelected = viewModel.percentageFromAmount
        viewModel.onPercentage(viewModel.percentageFromAmount)
        viewModel.validForm = true
    }

    private func makeViewModel(typing amount: String) throws -> UnstakeTransactionViewModel {
        let viewModel = UnstakeTransactionViewModel(
            coin: makeTCYCoin(),
            vault: TestStore.makeVault(),
            isAutocompound: false,
            availableToUnstake: staked
        )
        viewModel.availableAmount = staked
        type(amount, into: viewModel)
        return viewModel
    }

    private func memo(typing amount: String) throws -> String {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let viewModel = try makeViewModel(typing: amount)
        return try XCTUnwrap(viewModel.transactionBuilder).memo
    }

    // MARK: - The reported bug

    /// ⚠️ The regression test for the reported third symptom. Verified to FAIL on
    /// the parent commit, where the same inputs build `tcy-:5000` — 50% of
    /// 2002.74 = **1001.37**, exactly the figure the user reported receiving
    /// after asking for 1002.73.
    func testAWithdrawalAsksForTheAmountThatWasTypedNotAFlooredPercentage() throws {
        XCTAssertEqual(try memo(typing: "1002.73"), "tcy-:5006")
    }

    /// What the truncation cost, stated as money. 5006 bps of 2002.74 is
    /// 1002.5717; 5000 bps is 1001.37. The old path was off by 1.36 TCY, the new
    /// one by 0.16 — and never in the direction of taking more.
    func testBasisPointPrecisionLandsWithinOneBasisPointOfTheRequest() {
        let requested = Decimal(string: "1002.73")!
        let bps = TCYUnstakeBasisPoints.value(forAmount: requested, available: staked)
        let delivered = (staked * Decimal(bps)) / Decimal(TCYUnstakeBasisPoints.max)

        XCTAssertLessThanOrEqual(delivered, requested, "a withdrawal must never take more than was asked for")
        let error = NSDecimalNumber(decimal: requested - delivered).doubleValue
        XCTAssertLessThan(error, 0.21, "one basis point of this position is 0.20 TCY")
    }

    /// ⚠️ Rounding must never close a position the user asked to keep something
    /// in. Asking to withdraw 2002.64 of 2002.74 is asking to keep 0.10 TCY;
    /// rounding to nearest would reach 10000 and take the last of it, which is a
    /// different outcome rather than a rounding difference.
    func testRoundingNeverClosesAPositionTheUserAskedToKeep() {
        let bps = TCYUnstakeBasisPoints.value(forAmount: Decimal(string: "2002.64")!, available: staked)
        XCTAssertLessThan(bps, TCYUnstakeBasisPoints.max)
        XCTAssertEqual(bps, 9999)
    }

    // MARK: - Conversion

    func testHalfThePositionIsFiveThousandBasisPoints() {
        XCTAssertEqual(TCYUnstakeBasisPoints.value(forAmount: staked / 2, available: staked), 5000)
    }

    func testTheWholePositionIsTenThousandBasisPoints() {
        XCTAssertEqual(TCYUnstakeBasisPoints.value(forAmount: staked, available: staked), 10_000)
    }

    /// A memo can never ask for more of the position than all of it, whatever the
    /// field says.
    func testMoreThanThePositionClampsToTenThousand() {
        XCTAssertEqual(TCYUnstakeBasisPoints.value(forAmount: staked * 3, available: staked), 10_000)
    }

    func testAnAmountTooSmallForOneBasisPointIsZero() {
        // A basis point of this position is 0.200274 TCY.
        XCTAssertEqual(TCYUnstakeBasisPoints.value(forAmount: Decimal(string: "0.05")!, available: staked), 0)
    }

    func testThereAreNoBasisPointsOfAnEmptyPosition() {
        XCTAssertEqual(TCYUnstakeBasisPoints.value(forAmount: 10, available: 0), 0)
    }

    // MARK: - Closing the position

    /// A full exit has to pin the ceiling rather than derive it: the amount field
    /// renders 4 decimals, so on a small position MAX can round short and leave a
    /// sliver staked.
    func testClosingThePositionAsksForExactlyTenThousandBasisPoints() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let viewModel = UnstakeTransactionViewModel(
            coin: makeTCYCoin(),
            vault: TestStore.makeVault(),
            isAutocompound: false,
            availableToUnstake: staked
        )
        viewModel.availableAmount = staked
        viewModel.setupAmountField()          // MAX — what the sheet opens on
        viewModel.amountField.value = "2002.7400"
        viewModel.validForm = true

        XCTAssertEqual(try XCTUnwrap(viewModel.transactionBuilder).memo, "tcy-:10000")
    }

    // MARK: - Validation

    func testAnAmountBelowOneBasisPointIsRejected() {
        let validator = TCYUnstakeAmountValidator(available: staked, ticker: "TCY")
        XCTAssertThrowsError(try validator.validate(value: "0.05"))
    }

    /// The message has to name a figure that actually passes, or it sends the
    /// user in a circle.
    func testTheQuotedMinimumIsItselfAcceptable() throws {
        let validator = TCYUnstakeAmountValidator(available: staked, ticker: "TCY")
        let quoted = TCYUnstakeBasisPoints.quotedMinimum(
            forAvailable: staked,
            digits: TCYUnstakeAmountValidator.quotedDigits
        )
        XCTAssertNoThrow(
            try validator.validate(value: quoted.formatToDecimal(digits: TCYUnstakeAmountValidator.quotedDigits))
        )
        XCTAssertGreaterThanOrEqual(
            TCYUnstakeBasisPoints.value(forAmount: quoted, available: staked),
            TCYUnstakeBasisPoints.min
        )
    }

    /// ⚠️ A dust position must still be closable. Comparing against a minimum
    /// rounded up to display precision made any position smaller than that
    /// rounding unwithdrawable — not even at MAX, because the validator blocks
    /// the form before the builder is ever asked.
    func testADustPositionCanStillBeWithdrawnInFull() throws {
        let dust = Decimal(string: "0.00005")!
        let validator = TCYUnstakeAmountValidator(available: dust, ticker: "TCY")

        XCTAssertNoThrow(try validator.validate(value: "0.00005"))
        XCTAssertEqual(TCYUnstakeBasisPoints.value(forAmount: dust, available: dust), TCYUnstakeBasisPoints.max)
    }

    /// Reporting a malformed or over-balance amount is `AmountBalanceValidator`'s
    /// job; two validators reporting the same field would fight over the message.
    func testItLeavesMalformedAndOverBalanceAmountsToTheBalanceValidator() {
        let validator = TCYUnstakeAmountValidator(available: staked, ticker: "TCY")
        XCTAssertNoThrow(try validator.validate(value: "not a number"))
        XCTAssertNoThrow(try validator.validate(value: "0"))
        XCTAssertNoThrow(try validator.validate(value: "999999"))
    }

    /// A withdrawal too small to express must not reach the chain even if the
    /// validator is bypassed.
    func testTheBuilderRefusesAnAmountThatRoundsToNothing() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let viewModel = try makeViewModel(typing: "0.05")

        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - Scope

    /// bRUNE, RUJI-compound and CACAO reach the same view model through the same
    /// percentage expression and are deliberately left on it — this issue fences
    /// them off. If someone converts them later, this is the test that should be
    /// updated rather than silently passing.
    func testTheCacaoSiblingStillBuildsFromAWholePercentage() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let cacao = Coin(
            asset: TokensStore.cacao,
            address: "maya1fixturecacaovaultaddress000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        let viewModel = UnstakeTransactionViewModel(
            coin: cacao,
            vault: TestStore.makeVault(),
            isAutocompound: false,
            availableToUnstake: staked
        )
        viewModel.availableAmount = staked
        type("1002.73", into: viewModel)

        XCTAssertEqual(try XCTUnwrap(viewModel.transactionBuilder).memo, "POOL-:5000")
    }
}
