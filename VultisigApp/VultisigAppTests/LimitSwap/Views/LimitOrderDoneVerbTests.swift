//
//  LimitOrderDoneVerbTests.swift
//  VultisigAppTests
//
//  Pins the done-screen copy contract for `TransactionActionVerb.limitOrder`.
//
//  The verb is what stops the status header calling a resting order a
//  completed transaction. Two things are easy to get silently wrong and are
//  covered here:
//
//  1. A missing localisation degrades to the raw key on screen, and reads as
//     gibberish rather than as an obvious bug.
//  2. `CustomHighlightText` / `HighlightedText` match their highlight as a
//     SUBSTRING. A highlight that doesn't occur in its title matches nothing
//     and silently drops the accent — which is exactly what would happen if
//     the limit verb reused the generic "successful" highlight against
//     "Order filled".
//

import XCTest
@testable import VultisigApp

final class LimitOrderDoneVerbTests: XCTestCase {

    // MARK: - The order vocabulary is not the transaction vocabulary

    func testLimitOrderVerbUsesItsOwnKeysForEveryState() {
        let verb = TransactionActionVerb.limitOrder

        XCTAssertEqual(verb.broadcastedKey, "limitSwap.done.status.submitted")
        XCTAssertEqual(verb.pendingKey, "limitSwap.done.status.resting")
        XCTAssertEqual(verb.successfulKey, "limitSwap.done.status.filled")
        XCTAssertEqual(verb.failedKey, "limitSwap.done.status.closed")
    }

    /// "Order closed", never "Order not filled".
    ///
    /// An order can settle in two legs — expiring after a partial fill pays out
    /// what filled AND refunds the rest — so a frame that states nothing went
    /// through would be false for exactly the case that most needs care.
    func testTheTerminalFrameDoesNotClaimNothingFilled() {
        let title = TransactionActionVerb.limitOrder.failedKey.localized

        XCTAssertFalse(
            title.localizedCaseInsensitiveContains("not filled"),
            "A partially-filled order that then closed did fill — the title must not deny it"
        )
    }

    /// Same claim, in the reason lines. Only an outright placement failure may
    /// promise the funds came back whole, because only then did nothing fill.
    func testTerminalReasonsDoNotClaimAZeroFillExceptOnPlacementFailure() {
        for key in ["limitSwap.done.reason.refunded", "limitSwap.done.reason.expired", "limitSwap.done.reason.cancelled"] {
            let reason = key.localized
            XCTAssertFalse(
                reason.localizedCaseInsensitiveContains("without filling"),
                "\(key) states a zero fill as fact, which is false after a partial fill"
            )
            XCTAssertTrue(
                reason.localizedCaseInsensitiveContains("unfilled"),
                "\(key) should qualify what came back as the UNFILLED amount"
            )
        }
    }

    /// The regression guard. If the limit verb ever falls back to the `.send`
    /// keys, the done screen says "Transaction successful" about an order that
    /// has not filled.
    func testLimitOrderVerbSharesNoCopyWithTheGenericTransactionVerb() {
        let limit = TransactionActionVerb.limitOrder
        let send = TransactionActionVerb.send

        XCTAssertNotEqual(limit.broadcastedKey, send.broadcastedKey)
        XCTAssertNotEqual(limit.pendingKey, send.pendingKey)
        XCTAssertNotEqual(limit.successfulKey, send.successfulKey)
        XCTAssertNotEqual(limit.failedKey, send.failedKey)
    }

    // MARK: - Localisation actually resolves

    func testEveryLimitOrderKeyResolvesToRealCopy() {
        let verb = TransactionActionVerb.limitOrder
        let keys = [
            verb.broadcastedKey,
            verb.pendingKey,
            verb.successfulKey,
            verb.failedKey,
            verb.successfulHighlightKey,
            verb.failedHighlightKey,
            "limitSwap.done.status.restingDetail"
        ]

        for key in keys {
            let value = key.localized
            XCTAssertFalse(value.isEmpty, "\(key) resolved to an empty string")
            XCTAssertNotEqual(value, key, "\(key) has no localisation — the raw key would render on screen")
        }
    }

    // MARK: - Highlights must occur in the text they highlight

    func testHighlightsAreSubstringsOfTheirTitles() {
        let verb = TransactionActionVerb.limitOrder

        let successTitle = verb.successfulKey.localized
        let successHighlight = verb.successfulHighlightKey.localized
        XCTAssertTrue(
            successTitle.contains(successHighlight),
            "\(successHighlight.debugDescription) must occur in \(successTitle.debugDescription) or the accent is dropped"
        )

        let failedTitle = verb.failedKey.localized
        let failedHighlight = verb.failedHighlightKey.localized
        XCTAssertTrue(
            failedTitle.contains(failedHighlight),
            "\(failedHighlight.debugDescription) must occur in \(failedTitle.debugDescription) or the accent is dropped"
        )
    }

    /// Pre-existing verbs must keep the generic highlights they had before the
    /// per-verb split.
    func testExistingVerbsKeepTheGenericHighlights() {
        for verb in [TransactionActionVerb.send, .claim, .sign] {
            XCTAssertEqual(verb.successfulHighlightKey, "transactionSuccessfulHighlight")
            XCTAssertEqual(verb.failedHighlightKey, "transactionFailedHighlight")
        }
    }

    // MARK: - The resting detail line

    /// "Order placed" alone still reads like an ending. The detail line is
    /// what says the order is still waiting, so it must be present for the
    /// pending (resting) frame specifically.
    func testRestingFrameCarriesADetailLine() {
        XCTAssertEqual(
            TransactionActionVerb.limitOrder.detailKey(for: .pending),
            "limitSwap.done.status.restingDetail"
        )
    }

    func testNonRestingFramesCarryNoDetailLine() {
        let verb = TransactionActionVerb.limitOrder

        XCTAssertNil(verb.detailKey(for: .confirmed))
        XCTAssertNil(verb.detailKey(for: .broadcasted(estimatedTime: "~6 sec")))
        XCTAssertNil(verb.detailKey(for: .timeout))
        // `.failed` renders the reason carried on the status itself, which is
        // more specific than anything the verb could say.
        XCTAssertNil(verb.detailKey(for: .failed(reason: "anything")))
    }

    /// The detail line is additive: no pre-existing verb gains sub-copy.
    func testExistingVerbsHaveNoDetailLineInAnyState() {
        let states: [TransactionStatus] = [
            .broadcasted(estimatedTime: "~6 sec"), .pending, .confirmed,
            .failed(reason: "x"), .timeout
        ]

        for verb in [TransactionActionVerb.send, .claim, .sign] {
            for state in states {
                XCTAssertNil(verb.detailKey(for: state), "\(verb) must not gain sub-copy for \(state)")
            }
        }
    }
}
