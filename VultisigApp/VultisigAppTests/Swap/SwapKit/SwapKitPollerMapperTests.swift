//
//  SwapKitPollerMapperTests.swift
//  VultisigAppTests
//
//  Pure-function coverage for `SwapKitPoller.mapSwapKitStatus` — the
//  done-screen's `/track` → `TransactionStatus` mapping for SwapKit-routed
//  swaps. The mapping replaces the native per-chain RPC poller (which races
//  against the cross-chain leg) for these routes, so each
//  `SwapTrackingUiStatus` value must surface the right done-screen frame:
//
//    nil                     → broadcasted     (pre-attach frame, no /track data yet)
//    pending                 → pending         (source-chain phase: mempool/inbound/etc.)
//    swapping                → pending         (cross-chain leg in flight)
//    completed               → confirmed       (success / Rive success anim)
//    refunded                → failed("…")     (terminal — error frame)
//    failed                  → failed("…")     (terminal — error frame)
//    unknownPendingExtended  → pending         (don't flip to failure on outage)
//

import XCTest
@testable import VultisigApp

final class SwapKitPollerMapperTests: XCTestCase {

    private let estimatedTime = "~15-30 sec"

    func testNilStatusBeforeFirstPollReportsBroadcasted() {
        // Pre-attach frame — the view body renders once before `onAppear`
        // wires up `/track`, so the cache is empty. Show the "Broadcasted"
        // copy with the chain's estimated time, same as a non-SwapKit swap.
        let status = SwapKitPoller.mapSwapKitStatus(nil, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .broadcasted(estimatedTime: estimatedTime))
    }

    func testPendingStatusReportsPending() {
        // `/track` reports the source-chain phase (not_started/starting/
        // broadcasted/mempool/inbound/unknown collapse to UI `.pending`).
        // Once we have any `/track` data the user has moved past the raw
        // broadcast frame, so show "Pending" copy.
        let status = SwapKitPoller.mapSwapKitStatus(.pending, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .pending)
    }

    func testSwappingStatusReportsPending() {
        // Cross-chain leg in flight — header must *not* flip to confirmed
        // while the destination tx is still pending on the other side.
        let status = SwapKitPoller.mapSwapKitStatus(.swapping, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .pending)
    }

    func testCompletedStatusReportsConfirmed() {
        // The only path that surfaces the "Successful" / Rive success header.
        let status = SwapKitPoller.mapSwapKitStatus(.completed, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .confirmed)
    }

    func testRefundedStatusReportsFailedWithLocalisedReason() {
        let status = SwapKitPoller.mapSwapKitStatus(.refunded, estimatedTime: estimatedTime)
        guard case let .failed(reason) = status else {
            return XCTFail("Expected .failed for .refunded, got \(status)")
        }
        XCTAssertEqual(reason, "swapKitStatusRefundedReason".localized)
        XCTAssertFalse(reason.isEmpty, "Refund reason must be a real localised string")
    }

    func testFailedStatusReportsFailedWithLocalisedReason() {
        let status = SwapKitPoller.mapSwapKitStatus(.failed, estimatedTime: estimatedTime)
        guard case let .failed(reason) = status else {
            return XCTFail("Expected .failed for .failed, got \(status)")
        }
        XCTAssertEqual(reason, "swapKitStatusFailedReason".localized)
        XCTAssertFalse(reason.isEmpty, "Failure reason must be a real localised string")
    }

    func testUnknownExtendedReportsPendingNotFailed() {
        // Tracker outage — the swap is still in flight from the user's POV.
        // We must NOT surface a terminal `.failed` here, or the done-screen
        // would dishonestly call a still-running swap a failure.
        let status = SwapKitPoller.mapSwapKitStatus(.unknownPendingExtended, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .pending)
        XCTAssertFalse(status.isTerminal, "Tracker outage must not be terminal on the done screen")
    }

    func testTerminalCasesAreIsTerminal() {
        let completedTerminal = SwapKitPoller.mapSwapKitStatus(.completed, estimatedTime: estimatedTime).isTerminal
        let refundedTerminal = SwapKitPoller.mapSwapKitStatus(.refunded, estimatedTime: estimatedTime).isTerminal
        let failedTerminal = SwapKitPoller.mapSwapKitStatus(.failed, estimatedTime: estimatedTime).isTerminal
        XCTAssertTrue(completedTerminal)
        XCTAssertTrue(refundedTerminal)
        XCTAssertTrue(failedTerminal)
    }

    func testEstimatedTimeFlowsThroughOnlyForBroadcasted() {
        // `estimatedTime` is the broadcast-time copy from the chain config —
        // only the `.broadcasted` frame (returned for `nil` UI status, i.e.
        // the pre-attach pre-`/track` first paint) should display it; every
        // other frame uses fixed copy in `TransactionStatusHeaderView`.
        let broadcasted = SwapKitPoller.mapSwapKitStatus(nil, estimatedTime: "~30 min")
        XCTAssertEqual(broadcasted.broadcastedEstimatedTime, "~30 min")

        let pendingFromTrackerPending = SwapKitPoller.mapSwapKitStatus(.pending, estimatedTime: "~30 min")
        XCTAssertEqual(pendingFromTrackerPending.broadcastedEstimatedTime, "")

        let pendingFromSwapping = SwapKitPoller.mapSwapKitStatus(.swapping, estimatedTime: "~30 min")
        XCTAssertEqual(pendingFromSwapping.broadcastedEstimatedTime, "")
    }

    // MARK: - Limit-order states (defensive)

    /// `resting`/`expired`/`cancelled` belong to the THORChain limit provider
    /// and cannot reach this mapper — limit orders are routed to
    /// `LimitOrderPoller`. They are enumerated here (rather than swept into a
    /// `default`) so that adding a real SwapKit status later still fails the
    /// switch to compile.
    ///
    /// If one ever did arrive, the frame must claim neither success nor
    /// failure: this screen would be reporting on an order it knows nothing
    /// about.
    func testLimitOrderStatusesMapToPendingAndNeverClaimAnOutcome() {
        for status in [SwapTrackingUiStatus.resting, .expired, .cancelled] {
            let frame = SwapKitPoller.mapSwapKitStatus(status, estimatedTime: "~30 min")

            guard case .pending = frame else {
                return XCTFail("\(status) must map to .pending, got \(frame)")
            }
        }
    }
}
