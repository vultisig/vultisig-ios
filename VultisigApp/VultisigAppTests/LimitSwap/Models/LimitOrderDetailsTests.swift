//
//  LimitOrderDetailsTests.swift
//  VultisigAppTests
//
//  Covers the arithmetic the order card and detail sheet render:
//  the fill split (`LimitOrderFill`) and the expiry countdown
//  (`LimitOrderExpiry`).
//
//  These numbers describe a user's own funds mid-settlement, so the failure
//  mode that matters isn't a wrong pixel — it's confidently reporting that
//  money moved when it didn't, or vice versa.
//

import BigInt
import XCTest
@testable import VultisigApp

final class LimitOrderFillTests: XCTestCase {

    // MARK: - Unobserved is not zero

    func testUnobservedSplitKnowsNothingRatherThanReportingZero() {
        let fill = LimitOrderFill.unobserved

        XCTAssertNil(fill.fillFraction, "Never observed is not 0% — it's unknown")
        XCTAssertFalse(fill.isPartiallyFilled)
        XCTAssertNil(fill.refundedAmount)
        XCTAssertNil(fill.paidOutAmount)
    }

    func testZeroDepositIsTreatedAsUnknownRatherThanDividedBy() {
        let fill = LimitOrderFill(depositAmount: "0", filledInAmount: "0", filledOutAmount: "0")

        XCTAssertNil(fill.fillFraction)
        XCTAssertFalse(fill.isPartiallyFilled)
    }

    func testUnparseableAmountsAreUnknownRatherThanZero() {
        let fill = LimitOrderFill(depositAmount: "not-a-number", filledInAmount: "400", filledOutAmount: "50")

        XCTAssertNil(fill.fillFraction)
        XCTAssertFalse(fill.isPartiallyFilled)
    }

    // MARK: - Fraction

    func testFillFractionIsTheInOverDepositRatio() {
        let fill = LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "50")
        XCTAssertEqual(fill.fillFraction, Decimal(string: "0.4"))
    }

    func testFullyFilledReportsOne() {
        let fill = LimitOrderFill(depositAmount: "1000", filledInAmount: "1000", filledOutAmount: "500")
        XCTAssertEqual(fill.fillFraction, 1)
        XCTAssertFalse(fill.isPartiallyFilled, "Fully filled is not partially filled")
    }

    /// Not a state the protocol should produce; clamp rather than render >100%.
    func testOverfilledClampsToOne() {
        let fill = LimitOrderFill(depositAmount: "1000", filledInAmount: "1200", filledOutAmount: "600")
        XCTAssertEqual(fill.fillFraction, 1)
        XCTAssertFalse(fill.isPartiallyFilled)
    }

    /// THORChain accounts in `cosmos.Uint` (a big.Int). `Decimal` rounds past
    /// ~38 significant digits, so parsing these as `Decimal` could make two
    /// different amounts compare equal and report a partial fill as complete.
    func testHugeAmountsKeepExactIntegerPrecision() {
        let deposit = String(repeating: "9", count: 60)
        var filledDigits = Array(repeating: "9", count: 60)
        filledDigits[59] = "8" // one unit short of the deposit
        let filled = filledDigits.joined()

        let fill = LimitOrderFill(depositAmount: deposit, filledInAmount: filled, filledOutAmount: "1")

        XCTAssertTrue(
            fill.isPartiallyFilled,
            "One unit short of the deposit is a partial fill, however many digits it takes to say so"
        )
        XCTAssertEqual(fill.refundedAmount, 1)
    }

    // MARK: - isPartiallyFilled

    func testIsPartiallyFilledIsStrictlyBetweenZeroAndDeposit() {
        let zero = LimitOrderFill(depositAmount: "1000", filledInAmount: "0", filledOutAmount: "0")
        XCTAssertFalse(zero.isPartiallyFilled, "Nothing filled yet is not a partial fill")

        let partial = LimitOrderFill(depositAmount: "1000", filledInAmount: "1", filledOutAmount: "1")
        XCTAssertTrue(partial.isPartiallyFilled)
    }

    // MARK: - The two legs of a settlement

    func testRefundedAmountIsTheUnfilledRemainder() {
        let fill = LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "50")
        XCTAssertEqual(fill.refundedAmount, 600, "deposit - in is what comes back")
    }

    func testFullyFilledRefundsNothing() {
        let fill = LimitOrderFill(depositAmount: "1000", filledInAmount: "1000", filledOutAmount: "500")
        XCTAssertEqual(fill.refundedAmount, 0)
    }

    func testPaidOutIsTheTargetAssetLeg() {
        let fill = LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "50")
        XCTAssertEqual(fill.paidOutAmount, 50)
    }

    func testNegativePaidOutIsRejectedRatherThanRendered() {
        let fill = LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "-5")
        XCTAssertNil(fill.paidOutAmount)
    }
}

final class LimitOrderExpiryTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    func testSecondsRemainingIsBlocksTimesBlockTimeAtTheObservation() {
        let expiry = LimitOrderExpiry(blocksRemaining: 600, observedAt: anchor)
        // 600 blocks * ~6s = 3600s.
        XCTAssertEqual(expiry.secondsRemaining(now: anchor), 3600)
    }

    func testCountdownInterpolatesBetweenPolls() {
        // The tracker polls once a minute; the chip must tick in between rather
        // than sitting still and then jumping.
        let expiry = LimitOrderExpiry(blocksRemaining: 600, observedAt: anchor)
        XCTAssertEqual(expiry.secondsRemaining(now: anchor.addingTimeInterval(30)), 3570)
    }

    func testElapsedCountdownFloorsAtZeroRatherThanGoingNegative() {
        let expiry = LimitOrderExpiry(blocksRemaining: 10, observedAt: anchor)
        // 10 blocks = 60s; ask two minutes later.
        XCTAssertEqual(expiry.secondsRemaining(now: anchor.addingTimeInterval(120)), 0)
        XCTAssertTrue(expiry.hasElapsed(now: anchor.addingTimeInterval(120)))
    }

    func testNotElapsedWhileTimeRemains() {
        let expiry = LimitOrderExpiry(blocksRemaining: 600, observedAt: anchor)
        XCTAssertFalse(expiry.hasElapsed(now: anchor))
    }
}

final class LimitOrderDetailsTests: XCTestCase {

    func testOnlyPendingIsNonTerminal() {
        XCTAssertFalse(makeDetails(status: .pending).isTerminal)

        for status in [LimitOrderStatus.filled, .refunded, .expired, .cancelled] {
            XCTAssertTrue(makeDetails(status: status).isTerminal, "\(status) is terminal")
        }
    }

    /// A live order's unfilled remainder is still RESTING — it hasn't been
    /// refunded, and saying so would report funds returned that are still out.
    func testRestingOrderWithAnUnfilledRemainderIsNotReportedAsRefunded() {
        let details = makeDetails(
            status: .pending,
            fill: LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "50")
        )
        XCTAssertFalse(details.wasRefunded)
    }

    func testTerminalOrderWithAnUnfilledRemainderWasRefunded() {
        let details = makeDetails(
            status: .refunded,
            fill: LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "50")
        )
        XCTAssertTrue(details.wasRefunded)
    }

    func testTerminalFullyFilledOrderRefundedNothing() {
        let details = makeDetails(
            status: .filled,
            fill: LimitOrderFill(depositAmount: "1000", filledInAmount: "1000", filledOutAmount: "500")
        )
        XCTAssertFalse(details.wasRefunded, "Nothing was left over to refund")
    }

    // MARK: - The stale-snapshot trap

    /// The split we store is the last RESTING observation, taken up to a poll
    /// interval before the order closed. An order seen 40% filled that then
    /// COMPLETES leaves that 40% behind as its final snapshot.
    ///
    /// Read literally, `deposit - in` = 600 and the sheet would report a 600
    /// RUNE refund — money that was never sent back, stated as fact on a screen
    /// about the user's own funds. `.filled` means `In == Deposit` on-chain, so
    /// the status is the truth and the snapshot is merely stale.
    func testCompletedOrderWithAStalePartialSnapshotClaimsNoRefund() {
        let details = makeDetails(
            status: .filled,
            fill: LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "50")
        )

        XCTAssertFalse(details.wasRefunded, "A completed order refunded nothing, whatever the last snapshot caught")
    }

    /// Same trap, other row: a completed order must not be captioned
    /// "40% filled".
    func testCompletedOrderWithAStalePartialSnapshotIsNotReportedAsPartiallyFilled() {
        let details = makeDetails(
            status: .filled,
            fill: LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "50")
        )

        XCTAssertFalse(details.isPartiallyFilled, "`.filled` means it finished — the snapshot is just stale")
    }

    /// The guard must be narrow. A genuinely-partial REFUNDED order is the
    /// two-leg settlement this feature exists to show, and must survive.
    func testRefundedOrderWithAPartialSnapshotStillReportsBothLegs() {
        let details = makeDetails(
            status: .refunded,
            fill: LimitOrderFill(depositAmount: "1000", filledInAmount: "400", filledOutAmount: "50")
        )

        XCTAssertTrue(details.isPartiallyFilled)
        XCTAssertTrue(details.wasRefunded)
        XCTAssertEqual(details.fill.refundedAmount, 600)
        XCTAssertEqual(details.fill.paidOutAmount, 50)
    }

    func testUnobservedTerminalOrderMakesNoRefundClaim() {
        let details = makeDetails(status: .refunded, fill: .unobserved)
        XCTAssertFalse(details.wasRefunded, "Never observed the split — don't claim an amount came back")
    }

    // MARK: - Helpers

    private func makeDetails(status: LimitOrderStatus, fill: LimitOrderFill = .unobserved) -> LimitOrderDetails {
        LimitOrderDetails(
            id: "hash_pub",
            inboundTxHash: "HASH",
            sourceAsset: "THOR.RUNE",
            targetAsset: "BTC.BTC",
            targetPrice: 15,
            expiryBlocks: 7200,
            createdAt: Date(),
            status: status,
            minOutputOverride: nil,
            fill: fill,
            expiry: nil
        )
    }
}

final class LimitOrderFormattingTests: XCTestCase {

    func testPercentHasNoFractionalDigits() {
        // A streaming fill that's still moving doesn't have 39.7% of precision
        // to offer.
        XCTAssertEqual(LimitOrderFormatting.percent(Decimal(string: "0.397")!), "40%")
        XCTAssertEqual(LimitOrderFormatting.percent(Decimal(string: "0.4")!), "40%")
    }

    func testPercentClampsStrictlyPartialFractionsAwayFromTheBoundaries() {
        // Rounding alone would report the opposite of the truth at both ends:
        // untouched on an order that has started, complete on one still resting.
        XCTAssertEqual(LimitOrderFormatting.percent(Decimal(string: "0.000001")!), "1%")
        XCTAssertEqual(LimitOrderFormatting.percent(Decimal(string: "0.004")!), "1%")
        XCTAssertEqual(LimitOrderFormatting.percent(Decimal(string: "0.999999")!), "99%")
        XCTAssertEqual(LimitOrderFormatting.percent(Decimal(string: "0.997")!), "99%")
    }

    func testPercentKeepsTheExactBoundariesExact() {
        // The clamp must only move values that are strictly between 0 and 1 —
        // a genuinely untouched or genuinely complete order still says so.
        XCTAssertEqual(LimitOrderFormatting.percent(0), "0%")
        XCTAssertEqual(LimitOrderFormatting.percent(1), "100%")
    }

    func testCompactDurationCoarsensWithScale() {
        XCTAssertEqual(LimitOrderFormatting.compactDuration(2 * 86400 + 3 * 3600), "2d 3h")
        XCTAssertEqual(LimitOrderFormatting.compactDuration(11 * 3600 + 32 * 60), "11h 32m")
        XCTAssertEqual(LimitOrderFormatting.compactDuration(45 * 60), "45m")
        XCTAssertEqual(LimitOrderFormatting.compactDuration(30), "30s")
    }

    func testCompactDurationNeverRendersNegativeTime() {
        XCTAssertEqual(LimitOrderFormatting.compactDuration(-100), "0s")
    }
}
