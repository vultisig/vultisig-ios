//
//  SwapCryptoDoneViewSwapKitStatusTests.swift
//  VultisigAppTests
//
//  Pure-function coverage for `SwapCryptoDoneView.mapSwapKitStatus` — the
//  done-screen's `/track` → `TransactionStatus` mapping for SwapKit-routed
//  swaps. The mapping replaces the native per-chain RPC poller (which races
//  against the cross-chain leg) for these routes, so each `SwapKitUiStatus`
//  value must surface the right done-screen frame:
//
//    nil / pending           → broadcasted     (pre-`/track` UI)
//    swapping                → pending         (cross-chain leg in flight)
//    completed               → confirmed       (success / Rive success anim)
//    refunded                → failed("…")     (terminal — error frame)
//    failed                  → failed("…")     (terminal — error frame)
//    unknownPendingExtended  → pending         (don't flip to failure on outage)
//

import XCTest
@testable import VultisigApp

final class SwapCryptoDoneViewSwapKitStatusTests: XCTestCase {

    private let estimatedTime = "~15-30 sec"

    func testNilStatusBeforeFirstPollReportsBroadcasted() {
        let status = SwapCryptoDoneView.mapSwapKitStatus(nil, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .broadcasted(estimatedTime: estimatedTime))
    }

    func testPendingStatusReportsBroadcasted() {
        let status = SwapCryptoDoneView.mapSwapKitStatus(.pending, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .broadcasted(estimatedTime: estimatedTime))
    }

    func testSwappingStatusReportsPending() {
        // Cross-chain leg in flight — header should *not* flip to confirmed
        // while the destination tx is still pending on the other side.
        let status = SwapCryptoDoneView.mapSwapKitStatus(.swapping, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .pending)
    }

    func testCompletedStatusReportsConfirmed() {
        // The only path that surfaces the "Successful" / Rive success header.
        let status = SwapCryptoDoneView.mapSwapKitStatus(.completed, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .confirmed)
    }

    func testRefundedStatusReportsFailedWithLocalisedReason() {
        let status = SwapCryptoDoneView.mapSwapKitStatus(.refunded, estimatedTime: estimatedTime)
        guard case let .failed(reason) = status else {
            return XCTFail("Expected .failed for .refunded, got \(status)")
        }
        XCTAssertEqual(reason, "swapKitStatusRefundedReason".localized)
        XCTAssertFalse(reason.isEmpty, "Refund reason must be a real localised string")
    }

    func testFailedStatusReportsFailedWithLocalisedReason() {
        let status = SwapCryptoDoneView.mapSwapKitStatus(.failed, estimatedTime: estimatedTime)
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
        let status = SwapCryptoDoneView.mapSwapKitStatus(.unknownPendingExtended, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .pending)
        XCTAssertFalse(status.isTerminal, "Tracker outage must not be terminal on the done screen")
    }

    func testTerminalCasesAreIsTerminal() {
        let completedTerminal = SwapCryptoDoneView.mapSwapKitStatus(.completed, estimatedTime: estimatedTime).isTerminal
        let refundedTerminal = SwapCryptoDoneView.mapSwapKitStatus(.refunded, estimatedTime: estimatedTime).isTerminal
        let failedTerminal = SwapCryptoDoneView.mapSwapKitStatus(.failed, estimatedTime: estimatedTime).isTerminal
        XCTAssertTrue(completedTerminal)
        XCTAssertTrue(refundedTerminal)
        XCTAssertTrue(failedTerminal)
    }

    func testEstimatedTimeFlowsThroughOnlyForBroadcasted() {
        // `estimatedTime` is the broadcast-time copy from the chain config —
        // only the `.broadcasted` frame should display it; every other frame
        // uses fixed copy in `TransactionStatusHeaderView`.
        let broadcasted = SwapCryptoDoneView.mapSwapKitStatus(.pending, estimatedTime: "~30 min")
        XCTAssertEqual(broadcasted.broadcastedEstimatedTime, "~30 min")

        let pendingFromSwapping = SwapCryptoDoneView.mapSwapKitStatus(.swapping, estimatedTime: "~30 min")
        XCTAssertEqual(pendingFromSwapping.broadcastedEstimatedTime, "")
    }
}
