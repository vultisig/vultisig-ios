//
//  LimitOrderStatusDisplayTests.swift
//  VultisigAppTests
//
//  Pins what a limit order's card and detail sheet SAY about it.
//
//  Two properties matter most here and are easy to regress:
//
//  1. A partially-filled order is IN PROGRESS, not a fourth status. The
//     remainder is genuinely still resting, so the percentage is a qualifier on
//     the status line.
//  2. An expired or refunded order is NOT a failure. The row's coarse status
//     collapses refunded / expired / cancelled / failed all into `.error`, and
//     reading the display off that would tell a user their perfectly normal
//     expiry "went wrong".
//

import XCTest
@testable import VultisigApp

final class LimitOrderStatusDisplayTests: XCTestCase {

    // MARK: - Partial fill is a qualifier, not a status

    func testPartiallyFilledRestingOrderIsStillInProgressWithProgressDetail() {
        let display = LimitOrderStatusDisplay.make(
            uiStatus: .resting,
            details: makeDetails(status: .pending, deposit: "1000", filledIn: "400", filledOut: "50"),
            errorMessage: nil
        )

        XCTAssertEqual(display.kind, .inProgress, "A partial fill leaves the remainder resting — still in progress")
        XCTAssertEqual(display.detail, String(format: "limitSwap.progress.filledFormat".localized, "40%"))
    }

    func testUnfilledRestingOrderHasNoProgressDetail() {
        // 0% filled has nothing to report beyond its status.
        let display = LimitOrderStatusDisplay.make(
            uiStatus: .resting,
            details: makeDetails(status: .pending, deposit: "1000", filledIn: "0", filledOut: "0"),
            errorMessage: nil
        )

        XCTAssertEqual(display.kind, .inProgress)
        XCTAssertNil(display.detail)
    }

    func testFullyFilledOrderIsSuccessfulWithNoProgressDetail() {
        // 100% is just "Successful" — the amount pair above says the rest.
        let display = LimitOrderStatusDisplay.make(
            uiStatus: .completed,
            details: makeDetails(status: .filled, deposit: "1000", filledIn: "1000", filledOut: "500"),
            errorMessage: nil
        )

        XCTAssertEqual(display.kind, .successful)
        XCTAssertNil(display.detail)
    }

    /// The two-leg case: an order that expired 40% filled. The status says it
    /// closed; the detail says how much got through.
    func testTerminalAfterPartialFillKeepsTheProgressDetail() {
        let display = LimitOrderStatusDisplay.make(
            uiStatus: .refunded,
            details: makeDetails(status: .refunded, deposit: "1000", filledIn: "400", filledOut: "50"),
            errorMessage: nil
        )

        XCTAssertEqual(display.kind, .closedUnfilled(.refunded))
        XCTAssertEqual(display.detail, String(format: "limitSwap.progress.filledFormat".localized, "40%"))
    }

    /// A fill too small to round to 1% is still a partial fill — the remainder
    /// is still resting — so the order must not read as untouched.
    func testTinyPartialFillStillReportsProgress() {
        let display = LimitOrderStatusDisplay.make(
            uiStatus: .resting,
            details: makeDetails(status: .pending, deposit: "1000000", filledIn: "1", filledOut: "1"),
            errorMessage: nil
        )

        XCTAssertEqual(display.kind, .inProgress)
        XCTAssertNotNil(display.detail, "A sub-1% fill is still a partial fill")
    }

    // MARK: - Terminal-but-not-filled is not a failure

    func testClosedUnfilledStatusesAreNotFailures() {
        let cases: [(SwapTrackingUiStatus, LimitOrderStatusDisplay.ClosedReason)] = [
            (.refunded, .refunded),
            (.expired, .expired),
            (.cancelled, .cancelled)
        ]

        for (uiStatus, reason) in cases {
            let display = LimitOrderStatusDisplay.make(uiStatus: uiStatus, details: nil, errorMessage: nil)
            XCTAssertEqual(display.kind, .closedUnfilled(reason))
            XCTAssertNotEqual(display.kind, .failed, "\(uiStatus) is a normal outcome, not a failure")
            XCTAssertNotEqual(display.kind, .successful, "\(uiStatus) did not fill and must not read as success")
        }
    }

    func testOnlyFailedSurfacesTheRawErrorMessage() {
        // On-chain error text belongs to a real failure. Attaching it to an
        // expiry would explain a normal outcome as a fault.
        let failed = LimitOrderStatusDisplay.make(uiStatus: .failed, details: nil, errorMessage: "handler blew up")
        XCTAssertEqual(failed.kind, .failed)
        XCTAssertEqual(failed.detail, "handler blew up")

        let refunded = LimitOrderStatusDisplay.make(uiStatus: .refunded, details: nil, errorMessage: "handler blew up")
        XCTAssertNil(refunded.detail, "A refunded order must not borrow an error message")
    }

    func testFailedWithEmptyErrorMessageHasNoDetailLine() {
        let display = LimitOrderStatusDisplay.make(uiStatus: .failed, details: nil, errorMessage: "")
        XCTAssertEqual(display.kind, .failed)
        XCTAssertNil(display.detail, "An empty error string must not render a blank second line")
    }

    // MARK: - Resting never reads as done

    func testNoInFlightStatusEverReadsAsSuccessful() {
        for uiStatus in [SwapTrackingUiStatus.resting, .pending, .swapping, .unknownPendingExtended] {
            let display = LimitOrderStatusDisplay.make(uiStatus: uiStatus, details: nil, errorMessage: nil)
            XCTAssertEqual(display.kind, .inProgress, "\(uiStatus) is live, not done")
        }
    }

    // MARK: - Degrading without an order record

    /// A co-signer never persists a `LimitOrder`. The status must still
    /// resolve; only the progress detail is lost.
    func testStatusResolvesWithoutAnOrderRecord() {
        let display = LimitOrderStatusDisplay.make(uiStatus: .resting, details: nil, errorMessage: nil)
        XCTAssertEqual(display.kind, .inProgress)
        XCTAssertNil(display.detail)
    }

    // MARK: - Copy

    func testEveryStatusTitleResolvesToRealCopy() {
        let statuses: [SwapTrackingUiStatus] = [
            .resting, .pending, .swapping, .unknownPendingExtended,
            .completed, .refunded, .expired, .cancelled, .failed
        ]

        for uiStatus in statuses {
            let title = LimitOrderStatusDisplay.make(uiStatus: uiStatus, details: nil, errorMessage: nil).title
            XCTAssertFalse(title.isEmpty, "\(uiStatus) has an empty title")
            XCTAssertFalse(title.hasPrefix("limitSwap."), "\(uiStatus) title fell back to the raw key: \(title)")
        }
    }

    // MARK: - Helpers

    private func makeDetails(
        status: LimitOrderStatus,
        deposit: String?,
        filledIn: String?,
        filledOut: String?
    ) -> LimitOrderDetails {
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
            fill: LimitOrderFill(depositAmount: deposit, filledInAmount: filledIn, filledOutAmount: filledOut),
            expiry: nil
        )
    }
}
