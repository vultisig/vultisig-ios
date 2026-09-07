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

    // MARK: - Ticker stripping (shared by cryptoAmountText and swapLegsColumn)

    /// The `SwapDoneScreen` path pre-formats `"{amount} {ticker}"`; stripping
    /// isolates the bare number so it can be re-styled separately from the
    /// ticker.
    func testStripTickerRemovesASuffixThatIsPresent() {
        XCTAssertEqual(
            TransactionHistoryCardView.stripTicker(from: "200.50 SOL", ticker: "SOL"),
            "200.50"
        )
    }

    /// The co-signer's `TransactionHistoryRecorder.recordFromKeysignPayload`
    /// records `toAmountCrypto` as a bare number with no ticker suffix at
    /// all — the exact case that regressed the swap-legs ticker. Stripping
    /// must be a no-op here, not eat digits off the amount.
    func testStripTickerIsANoOpWhenTheSuffixIsAbsent() {
        XCTAssertEqual(
            TransactionHistoryCardView.stripTicker(from: "200.50", ticker: "SOL"),
            "200.50"
        )
    }

    /// A custom token's ticker can look like the tail of a decimal amount
    /// (e.g. a ticker of "50"). Matching only the SPACE-delimited suffix
    /// keeps this a no-op instead of chewing digits off the amount.
    func testStripTickerDoesNotEatDigitsFromAnAmbiguousNumericTicker() {
        XCTAssertEqual(
            TransactionHistoryCardView.stripTicker(from: "200.50", ticker: "50"),
            "200.50"
        )
    }

    // MARK: - Completed swap/limit legs routing

    /// A completed swap or limit row with both amounts known gets the
    /// two-leg layout.
    func testShowsSwapLegsForCompleteSwapOrLimitData() {
        for type in [TransactionHistoryType.swap, .limit] {
            XCTAssertTrue(
                TransactionHistoryCardView.showsSwapLegs(
                    type: type,
                    toAmountCrypto: "200.50 SOL",
                    toCoinTicker: "SOL"
                ),
                "\(type) with a known to-side must show the legs"
            )
        }
    }

    /// Send, approve, and trust-line rows never get the swap legs — they
    /// have nothing to pair.
    func testShowsSwapLegsFalseForNonSwapTypes() {
        for type in [TransactionHistoryType.send, .approve, .trustLineActivation] {
            XCTAssertFalse(
                TransactionHistoryCardView.showsSwapLegs(
                    type: type,
                    toAmountCrypto: "200.50 SOL",
                    toCoinTicker: "SOL"
                ),
                "\(type) must never show the swap legs"
            )
        }
    }

    /// A native-source limit order (`recordLimitOrder`) never resolves the
    /// to-side, so it keeps today's single fiat/crypto amount instead of
    /// claiming a pair it cannot show.
    func testShowsSwapLegsFalseWithoutAKnownToSide() {
        XCTAssertFalse(
            TransactionHistoryCardView.showsSwapLegs(type: .limit, toAmountCrypto: nil, toCoinTicker: nil)
        )
        XCTAssertFalse(
            TransactionHistoryCardView.showsSwapLegs(type: .limit, toAmountCrypto: "", toCoinTicker: "SOL")
        )
        XCTAssertFalse(
            TransactionHistoryCardView.showsSwapLegs(type: .limit, toAmountCrypto: "1 SOL", toCoinTicker: "")
        )
    }

    // MARK: - Via badge routing

    /// The badge disappears only once a COMPLETED row is already showing
    /// the swap legs — the `FROM → TO` pill takes over naming the route.
    func testShowsViaBadgeFalseOnlyForACompletedRowWithSwapLegs() {
        XCTAssertFalse(
            TransactionHistoryCardView.showsViaBadge(hasProvider: true, isExpanded: false, showsSwapLegs: true)
        )
    }

    /// An in-progress swap row keeps the badge even though it will show the
    /// legs once it completes — `expandedContent` names both coins but not
    /// the provider.
    func testShowsViaBadgeTrueWhileInProgressEvenWithSwapLegs() {
        XCTAssertTrue(
            TransactionHistoryCardView.showsViaBadge(hasProvider: true, isExpanded: true, showsSwapLegs: true)
        )
    }

    /// A completed row that can't show the legs (no known to-side) still
    /// needs the badge to say what it routed through.
    func testShowsViaBadgeTrueForACompletedRowWithoutSwapLegs() {
        XCTAssertTrue(
            TransactionHistoryCardView.showsViaBadge(hasProvider: true, isExpanded: false, showsSwapLegs: false)
        )
    }

    /// No provider, no badge, regardless of everything else.
    func testShowsViaBadgeFalseWithoutAProvider() {
        for isExpanded in [true, false] {
            for showsSwapLegs in [true, false] {
                XCTAssertFalse(
                    TransactionHistoryCardView.showsViaBadge(
                        hasProvider: false,
                        isExpanded: isExpanded,
                        showsSwapLegs: showsSwapLegs
                    )
                )
            }
        }
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
