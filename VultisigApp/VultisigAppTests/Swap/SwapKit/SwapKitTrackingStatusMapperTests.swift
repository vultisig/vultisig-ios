//
//  SwapKitTrackingStatusMapperTests.swift
//  VultisigAppTests
//
//  Pure-function coverage for the 14-value `TrackingStatus → SwapTrackingUiStatus`
//  table documented in `track-in-tx-history-plan.md` §"State mapping".
//  Augmented with edge cases:
//
//   * Unknown / missing strings collapse to `.pending` rather than crashing.
//   * Coarse-status fallback path matches the table at coarser granularity.
//   * Case-insensitive — the wire enum is lowercase but tests assert tolerance
//     for SDK quirks (the docs vs npm enums disagree on casing).
//

import XCTest
@testable import VultisigApp

final class SwapKitTrackingStatusMapperTests: XCTestCase {

    // MARK: - TrackingStatus → UI mapping

    func testPendingStatusesMapToPending() {
        for raw in ["not_started", "starting", "broadcasted", "mempool", "inbound"] {
            XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: raw), .pending, "Expected pending for \(raw)")
        }
    }

    func testSwappingStatusesMapToSwapping() {
        for raw in ["outbound", "swapping"] {
            XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: raw), .swapping, "Expected swapping for \(raw)")
        }
    }

    func testCompletedMapsToCompleted() {
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: "completed"), .completed)
    }

    func testRefundedStatusesMapToRefunded() {
        for raw in ["refunded", "partially_refunded"] {
            XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: raw), .refunded, "Expected refunded for \(raw)")
        }
    }

    func testFailedStatusesMapToFailed() {
        for raw in ["dropped", "reverted", "replaced", "retries_exceeded", "parsing_error", "failed"] {
            XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: raw), .failed, "Expected failed for \(raw)")
        }
    }

    func testUnknownStatusMapsToPending() {
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: "unknown"), .pending)
    }

    func testNilAndEmptyStatusMapToPending() {
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: nil), .pending)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: ""), .pending)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: "COMPLETED"), .completed)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: "Refunded"), .refunded)
    }

    func testUnrecognisedStatusDefaultsToPending() {
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: "something_new"), .pending)
    }

    // MARK: - Coarse-status fallback

    func testCoarseStatusFallbackPaths() {
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(coarseStatus: .notStarted), .pending)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(coarseStatus: .pending), .pending)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(coarseStatus: .swapping), .swapping)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(coarseStatus: .completed), .completed)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(coarseStatus: .refunded), .refunded)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(coarseStatus: .failed), .failed)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(coarseStatus: .unknown), .pending)
    }

    // MARK: - Combined precedence

    func testFineGrainedTrackingStatusTakesPrecedence() {
        // coarse says completed, but trackingStatus says inbound → expect pending
        let response = makeResponse(status: .completed, trackingStatus: "inbound")
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(response), .pending)
    }

    func testFallsBackToCoarseWhenFineGrainedAbsent() {
        let response = makeResponse(status: .swapping, trackingStatus: nil)
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(response), .swapping)
    }

    func testFallsBackToCoarseWhenFineGrainedEmpty() {
        let response = makeResponse(status: .refunded, trackingStatus: "")
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(response), .refunded)
    }

    // MARK: - isTerminal

    func testIsTerminalCoversAll() {
        XCTAssertTrue(SwapTrackingUiStatus.completed.isTerminal)
        XCTAssertTrue(SwapTrackingUiStatus.refunded.isTerminal)
        XCTAssertTrue(SwapTrackingUiStatus.failed.isTerminal)
        XCTAssertTrue(SwapTrackingUiStatus.unknownPendingExtended.isTerminal)
        XCTAssertFalse(SwapTrackingUiStatus.pending.isTerminal)
        XCTAssertFalse(SwapTrackingUiStatus.swapping.isTerminal)
    }

    // MARK: - Full state-transition sequence

    func testHappyPathStateTransition() {
        // not_started → starting → broadcasted → mempool → inbound → swapping → outbound → completed
        let sequence: [(String, SwapTrackingUiStatus)] = [
            ("not_started", .pending),
            ("starting", .pending),
            ("broadcasted", .pending),
            ("mempool", .pending),
            ("inbound", .pending),
            ("swapping", .swapping),
            ("outbound", .swapping),
            ("completed", .completed)
        ]
        for (raw, expected) in sequence {
            XCTAssertEqual(
                SwapKitTrackingStatusMapper.map(trackingStatus: raw),
                expected,
                "Sequence step \(raw) should map to \(expected)"
            )
        }
    }

    func testRefundPathTransition() {
        let sequence: [(String, SwapTrackingUiStatus)] = [
            ("broadcasted", .pending),
            ("mempool", .pending),
            ("inbound", .pending),
            ("refunded", .refunded)
        ]
        for (raw, expected) in sequence {
            XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: raw), expected)
        }
    }

    func testPartiallyRefundedAlsoTerminal() {
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: "partially_refunded"), .refunded)
        XCTAssertTrue(SwapTrackingUiStatus.refunded.isTerminal)
    }

    func testAllDocumentedFailureTerminalsMapToFailed() {
        let terminals = ["dropped", "reverted", "replaced", "retries_exceeded", "parsing_error"]
        for raw in terminals {
            XCTAssertEqual(
                SwapKitTrackingStatusMapper.map(trackingStatus: raw),
                .failed,
                "\(raw) should be terminal-failed"
            )
        }
    }

    // MARK: - Fixtures

    private func makeResponse(
        status: SwapKitTrackingStatus,
        trackingStatus: String?
    ) -> SwapKitTrackingResponse {
        SwapKitTrackingResponse(
            chainId: "1",
            hash: "0xdeadbeef",
            block: nil,
            type: "swap",
            status: status,
            trackingStatus: trackingStatus,
            fromAsset: nil,
            fromAmount: nil,
            fromAddress: nil,
            toAsset: nil,
            toAmount: nil,
            toAddress: nil,
            finalisedAt: nil
        )
    }
}
