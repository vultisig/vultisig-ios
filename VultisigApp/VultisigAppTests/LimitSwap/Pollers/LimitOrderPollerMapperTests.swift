//
//  LimitOrderPollerMapperTests.swift
//  VultisigAppTests
//
//  Pure-function coverage for `LimitOrderPoller.mapLimitStatus` — the
//  done-screen's limit-queue → `TransactionStatus` mapping.
//
//  This mapping exists to kill one specific, highly visible lie: before it, a
//  limit order fell through to the source-chain `ChainPoller`, which confirms
//  the INBOUND DEPOSIT and so reported "Transaction successful" seconds after
//  the user placed an order that may rest unfilled for 12-72h.
//
//    nil                     → broadcasted   (pre-attach frame, no queue data yet)
//    resting                 → pending       (THE fix: placed, live, NOT filled)
//    pending / swapping      → pending       (generic in-flight row status)
//    unknownPendingExtended  → pending       (never claim an outcome on an outage)
//    completed               → confirmed     (the ONLY success — it actually filled)
//    refunded                → failed(…)     (terminal, did not fill)
//    expired                 → failed(…)     (terminal, did not fill)
//    cancelled               → failed(…)     (terminal, did not fill)
//    failed                  → failed(…)     (terminal, did not fill)
//

import XCTest
@testable import VultisigApp

final class LimitOrderPollerMapperTests: XCTestCase {

    private let estimatedTime = "~10-60 min"

    // MARK: - The regression this whole type exists for

    /// The headline guarantee. A resting order is live and unfilled; the done
    /// screen must never render the success frame for it.
    func testRestingNeverReportsConfirmed() {
        let status = LimitOrderPoller.mapLimitStatus(.resting, estimatedTime: estimatedTime)

        XCTAssertEqual(status, .pending)
        XCTAssertNotEqual(status, .confirmed, "A resting limit order must never read as successful")
        XCTAssertFalse(status.isTerminal, "A resting order is still live — nothing about it is terminal")
    }

    /// Belt-and-braces on the same guarantee, stated as an invariant over the
    /// whole vocabulary: `.completed` is the sole route to the success frame.
    /// If a future status is added and casually mapped to `.confirmed`, this
    /// fails.
    func testOnlyCompletedEverReportsConfirmed() {
        let nonFilled: [SwapTrackingUiStatus] = [
            .resting, .pending, .swapping, .unknownPendingExtended,
            .refunded, .expired, .cancelled, .failed
        ]

        for status in nonFilled {
            let frame = LimitOrderPoller.mapLimitStatus(status, estimatedTime: estimatedTime)
            XCTAssertNotEqual(
                frame, .confirmed,
                "\(status) does not mean the order filled — it must not reach the success frame"
            )
        }

        XCTAssertEqual(LimitOrderPoller.mapLimitStatus(.completed, estimatedTime: estimatedTime), .confirmed)
    }

    // MARK: - Pre-attach

    func testNilStatusBeforeFirstPollReportsBroadcasted() {
        // The poller is constructed before `start()` seeds the cache.
        let status = LimitOrderPoller.mapLimitStatus(nil, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .broadcasted(estimatedTime: estimatedTime))
    }

    func testEstimatedTimeFlowsThroughOnlyForBroadcasted() {
        let broadcasted = LimitOrderPoller.mapLimitStatus(nil, estimatedTime: "~30 min")
        XCTAssertEqual(broadcasted.broadcastedEstimatedTime, "~30 min")

        let resting = LimitOrderPoller.mapLimitStatus(.resting, estimatedTime: "~30 min")
        XCTAssertEqual(resting.broadcastedEstimatedTime, "")
    }

    // MARK: - In-flight

    func testGenericInFlightStatusesReportPending() {
        for status in [SwapTrackingUiStatus.pending, .swapping] {
            XCTAssertEqual(
                LimitOrderPoller.mapLimitStatus(status, estimatedTime: estimatedTime), .pending,
                "\(status) is in-flight, not an outcome"
            )
        }
    }

    func testUnknownExtendedReportsPendingNotFailed() {
        // The limit tracker never promotes to this (handing authority back to
        // the deposit-confirming native poller is the bug), but a row could
        // carry it from another provider's write. Claim nothing.
        let status = LimitOrderPoller.mapLimitStatus(.unknownPendingExtended, estimatedTime: estimatedTime)
        XCTAssertEqual(status, .pending)
        XCTAssertFalse(status.isTerminal)
    }

    // MARK: - Terminal, but not filled

    func testTerminalNonFilledStatusesReportFailedWithDistinctLocalisedReasons() {
        let expected: [SwapTrackingUiStatus: String] = [
            .refunded: "limitSwap.done.reason.refunded".localized,
            .expired: "limitSwap.done.reason.expired".localized,
            .cancelled: "limitSwap.done.reason.cancelled".localized,
            .failed: "limitSwap.done.reason.failed".localized
        ]

        for (status, expectedReason) in expected {
            let frame = LimitOrderPoller.mapLimitStatus(status, estimatedTime: estimatedTime)
            guard case let .failed(reason) = frame else {
                return XCTFail("Expected .failed for \(status), got \(frame)")
            }
            XCTAssertEqual(reason, expectedReason)
            XCTAssertFalse(reason.isEmpty, "\(status) reason must be a real localised string, not a missing key")
            XCTAssertFalse(
                reason.hasPrefix("limitSwap."),
                "\(status) reason fell back to the raw key — the localisation is missing"
            )
            XCTAssertTrue(frame.isTerminal)
        }

        // Each terminal state says something different — otherwise the reason
        // line adds nothing over the title.
        let reasons = Set(expected.values)
        XCTAssertEqual(reasons.count, expected.count, "Terminal reasons must be distinguishable from each other")
    }
}
