//
//  AmountPercentageBindingTests.swift
//  VultisigAppTests
//
//  The amount ↔ percentage binding behind every stake / unstake / LP amount
//  field. Typing an amount used to blank the percentage, which left the slider
//  showing its `percentage ?? 100` fallback: a confident 100% under an amount
//  the user had typed as something else entirely.
//

@testable import VultisigApp
import XCTest

final class AmountPercentageBindingTests: XCTestCase {

    private func percentage(_ amount: String, of available: String) -> Double? {
        AmountPercentageBinding.percentage(
            ofAmount: Decimal(string: amount)!,
            available: Decimal(string: available)!
        )
    }

    /// The reported position: 1002.73 typed against 2002.74 staked is a hair
    /// over half, and the slider has to say so rather than claiming 100%.
    func testATypedAmountDerivesItsShareOfTheBalance() throws {
        let derived = try XCTUnwrap(percentage("1002.73", of: "2002.74"))
        XCTAssertEqual(derived, 50.0679, accuracy: 0.0001)
    }

    func testTheWholeBalanceIsAHundredPercent() {
        XCTAssertEqual(percentage("2002.74", of: "2002.74"), 100)
    }

    func testNothingTypedIsZeroPercent() {
        XCTAssertEqual(percentage("0", of: "2002.74"), 0)
    }

    /// The field has to accept an over-balance figure so the balance validator
    /// can report it, but the slider's range is `0...100` — an unclamped
    /// percentage would drive it off its own track.
    func testAnAmountOverTheBalanceClampsToAHundred() {
        XCTAssertEqual(percentage("5000", of: "2002.74"), 100)
    }

    /// No balance is not 0% of something, it is a percentage that does not
    /// exist — and dividing by it would trap.
    func testThereIsNoPercentageOfAnEmptyBalance() {
        XCTAssertNil(percentage("10", of: "0"))
    }

    // MARK: - Which side the user owns
    //
    // The part of the amount field most able to move money incorrectly: it decides
    // whether the slider may overwrite a figure the user typed. Reverting any of
    // these behaviours in `AmountPercentageSync` fails a test here.

    /// Typing writes the percentage, so the field then sees its own write arrive
    /// on the same channel a real slider interaction uses. It must not treat that
    /// as a reason to rewrite the amount — that is the feedback loop blanking the
    /// percentage used to prevent.
    func testTheFieldsOwnDerivedWriteIsIgnored() {
        var sync = AmountPercentageSync()
        sync.amountWasTyped(derivingPercentage: 50.0679)

        XCTAssertEqual(sync.percentageChanged(to: 50.0679), .ignore)
    }

    func testARealSliderMoveMayRewriteTheAmount() {
        var sync = AmountPercentageSync()
        sync.amountWasTyped(derivingPercentage: 50.0679)

        XCTAssertEqual(sync.percentageChanged(to: 75), .setAmountFromPercentage)
    }

    /// ⚠️ The derived value is SPENT by a real interaction. Remembering it
    /// forever would suppress a later move back to the same percentage: type the
    /// full balance (derives 100), drag to 99%, drag back to 100% — that last
    /// move would be read as the original echo, leaving the amount at 99% while
    /// the screen reported a MAX withdrawal.
    func testMovingBackToADerivedPercentageIsStillARealInteraction() {
        var sync = AmountPercentageSync()
        sync.amountWasTyped(derivingPercentage: 100)

        XCTAssertEqual(sync.percentageChanged(to: 99), .setAmountFromPercentage)
        XCTAssertEqual(sync.percentageChanged(to: 100), .setAmountFromPercentage)
    }

    /// A balance landing after the user has typed must not overwrite what they
    /// typed — the percentage is re-derived against the new balance instead.
    func testALateBalanceKeepsATypedAmountAndRederivesThePercentage() {
        var sync = AmountPercentageSync()
        sync.amountWasTyped(derivingPercentage: 50)

        XCTAssertEqual(sync.balanceChanged(), .derivePercentageFromAmount)
    }

    /// ⚠️ A percentage derived against an empty balance is `nil`, so the value
    /// alone cannot say the amount was typed. Tracking only the value left this
    /// case stuck: the amount stayed, the slider kept rendering its 100%
    /// fallback, and a stale `isMaxAmount` survived.
    func testAnAmountTypedBeforeTheBalanceArrivedIsStillTheUsers() {
        var sync = AmountPercentageSync()
        sync.amountWasTyped(derivingPercentage: nil)

        XCTAssertEqual(sync.balanceChanged(), .derivePercentageFromAmount)
    }

    /// Nothing typed: the percentage is in charge, which is what makes a screen
    /// that opens on MAX fill its amount in.
    func testWithNothingTypedThePercentageDrivesTheAmount() {
        let sync = AmountPercentageSync()
        XCTAssertEqual(sync.balanceChanged(), .setAmountFromPercentage)
    }

    /// After the slider takes over, a later balance change belongs to it again.
    func testASliderMoveHandsOwnershipBackToThePercentage() {
        var sync = AmountPercentageSync()
        sync.amountWasTyped(derivingPercentage: 50)
        _ = sync.percentageChanged(to: 75)

        XCTAssertEqual(sync.balanceChanged(), .setAmountFromPercentage)
    }

    /// A screen whose percentage starts `nil` and whose field starts empty must
    /// not be told the (absent) amount is the user's.
    func testAFreshFieldIsNotConsideredUserTyped() {
        let sync = AmountPercentageSync()
        XCTAssertFalse(sync.amountIsUserTyped)
        XCTAssertNil(sync.lastDerivedPercentage)
    }

    func testPercentageAndAmountRoundTrip() throws {
        let available = Decimal(string: "2002.74")!
        let derived = try XCTUnwrap(AmountPercentageBinding.percentage(ofAmount: Decimal(string: "500.685")!, available: available))
        let back = AmountPercentageBinding.amount(forPercentage: derived, available: available)
        XCTAssertEqual(NSDecimalNumber(decimal: back).doubleValue, 500.685, accuracy: 0.0001)
    }
}
