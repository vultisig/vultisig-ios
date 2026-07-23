//
//  TransactionHistoryCardViewTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TransactionHistoryCardViewTests: XCTestCase {
    func testCompletedTransactionsNeverExpand() {
        for status in [TransactionHistoryStatus.successful, .error] {
            XCTAssertFalse(TransactionHistoryCardView.shouldExpand(status: status, type: .send))
            XCTAssertFalse(TransactionHistoryCardView.shouldExpand(status: status, type: .swap))
            XCTAssertFalse(TransactionHistoryCardView.shouldExpand(status: status, type: .approve))
        }
    }

    func testInProgressTransactionExpandsUnlessItIsApproval() {
        XCTAssertTrue(TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .send))
        XCTAssertTrue(TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .swap))
        XCTAssertFalse(TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .approve))
    }

    // MARK: - Limit routing: in-progress pill vs closed status line

    /// A live order — resting OR cancelling — shows the in-progress pill, not the
    /// closed status line. The authoritative order wins over a lagging row: a
    /// `.cancelling` order is still live the instant the order says so.
    func testLiveLimitOrderIsNotTerminalEvenWithALaggingRow() {
        for status in [LimitOrderStatus.pending, .cancelling] {
            XCTAssertFalse(
                TransactionHistoryCardView.isLimitTerminal(
                    limitOrder: makeLimitDetails(status: status),
                    uiStatus: .resting
                ),
                "\(status) is live and must show the pill"
            )
        }
    }

    /// A closed order shows its status line.
    func testClosedLimitOrderIsTerminal() {
        for status in [LimitOrderStatus.filled, .refunded, .expired, .cancelled] {
            XCTAssertTrue(
                TransactionHistoryCardView.isLimitTerminal(
                    limitOrder: makeLimitDetails(status: status),
                    uiStatus: .resting
                ),
                "\(status) is closed and must show the status line"
            )
        }
    }

    /// The order outranks the row even when the row has (wrongly) gone terminal.
    func testAuthoritativeOrderWinsOverAStaleTerminalRow() {
        XCTAssertFalse(
            TransactionHistoryCardView.isLimitTerminal(
                limitOrder: makeLimitDetails(status: .cancelling),
                uiStatus: .cancelled
            ),
            "a live order is live regardless of a stale row"
        )
    }

    /// A co-signer holds no order and falls back to the row's mirror.
    func testCoSignerWithoutAnOrderFallsBackToTheRow() {
        XCTAssertFalse(TransactionHistoryCardView.isLimitTerminal(limitOrder: nil, uiStatus: .resting))
        XCTAssertTrue(TransactionHistoryCardView.isLimitTerminal(limitOrder: nil, uiStatus: .refunded))
    }

    /// ⚠️ The pill routing and the status display MUST agree on `.failed`. The
    /// pill routing resolves through the same `effectiveUiStatus` the display
    /// uses, so a `.failed` row is treated as terminal (status line, not pill)
    /// even with a non-terminal order behind it — the card and the detail sheet
    /// can never split into "In progress" here and "Error" there.
    func testAFailedRowRoutesTerminalMatchingTheDisplay() {
        let details = makeLimitDetails(status: .pending)

        XCTAssertTrue(
            TransactionHistoryCardView.isLimitTerminal(limitOrder: details, uiStatus: .failed),
            "a failed row is terminal for routing"
        )
        // ...and the display agrees it is `.failed`, not in-progress.
        let display = LimitOrderStatusDisplay.make(uiStatus: .failed, details: details, errorMessage: "boom")
        XCTAssertEqual(display.kind, .failed)
    }

    // MARK: - Helpers

    private func makeLimitDetails(status: LimitOrderStatus) -> LimitOrderDetails {
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
            fill: LimitOrderFill(depositAmount: nil, filledInAmount: nil, filledOutAmount: nil),
            expiry: nil
        )
    }
}
