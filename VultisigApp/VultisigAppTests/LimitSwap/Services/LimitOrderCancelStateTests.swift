//
//  LimitOrderCancelStateTests.swift
//  VultisigAppTests
//
//  Post-cancel state. The invariant under test is that a cancel is recorded as
//  an INTENT and only becomes `.cancelled` once the chain confirms the order
//  actually closed — a cancel that matches nothing must stay visibly resting.
//

import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrderCancelStateTests: XCTestCase {

    private static let observedAt = Date(timeIntervalSince1970: 1_000_000)

    private func makeOrder(
        status: LimitOrderStatus = .pending,
        cancelBroadcastHash: String? = nil,
        blocksToExpiry: Int? = nil
    ) -> LimitOrder {
        let order = LimitOrder(
            id: "order-1",
            inboundTxHash: "ABC123",
            sourceAsset: "THOR.RUNE",
            sourceAmount: "100000000",
            sourceDecimals: 8,
            targetAsset: "BTC.BTC",
            destAddress: "bc1qdest",
            targetPrice: 1,
            expiryBlocks: 14_400,
            createdAt: Date(),
            status: status,
            vault: .example
        )
        order.cancelBroadcastHash = cancelBroadcastHash
        if let blocksToExpiry {
            order.timeToExpiryBlocks = blocksToExpiry
            order.expiryObservedAt = Self.observedAt
        }
        return order
    }

    // MARK: - Reconciliation

    /// The queue only ever reports that funds came back. Only this device knows
    /// it asked for that — `EventLimitSwapClose` carries the reason and reaches
    /// no REST route, so without this the user who cancelled sees "Refunded".
    func testRefundOnAnOrderWeCancelledIsReportedAsCancelled() {
        let order = makeOrder(cancelBroadcastHash: "CANCELTX")

        XCTAssertEqual(LimitOrderStorageService.reconcile(observed: .refunded, with: order), .cancelled)
    }

    func testRefundWithoutACancelStaysRefunded() {
        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .refunded, with: makeOrder()),
            .refunded
        )
    }

    /// ⚠️ An order that FILLED before the cancel landed genuinely filled.
    /// Relabelling that as cancelled would tell the user their funds came back
    /// when they were actually swapped.
    func testFillIsNeverRelabelledAsCancelledEvenAfterACancelWasBroadcast() {
        let order = makeOrder(cancelBroadcastHash: "CANCELTX")

        XCTAssertEqual(LimitOrderStorageService.reconcile(observed: .filled, with: order), .filled)
    }

    // MARK: - TTL ambiguity beats an outstanding cancel intent

    /// ⚠️ The delayed form of the failure the intent-record design exists to
    /// avoid. A cancel that addressed the wrong ratio bucket does nothing; hours
    /// later the order expires on its own. Crediting that closure to the cancel
    /// would tell the user their cancel worked when it silently failed.
    func testClosureAtOrAfterExpiryIsNotCreditedToTheCancel() {
        // 10 blocks x 6s = 60s of runway from the anchor.
        let order = makeOrder(cancelBroadcastHash: "CANCELTX", blocksToExpiry: 10)

        let atExpiry = Self.observedAt.addingTimeInterval(60)
        let afterExpiry = Self.observedAt.addingTimeInterval(600)

        // `.refunded`, not `.expired`: once the TTL is in play the two causes
        // are indistinguishable, and asserting either would be an overclaim.
        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .refunded, with: order, now: atExpiry),
            .refunded
        )
        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .refunded, with: order, now: afterExpiry),
            .refunded
        )
    }

    /// The mirror case: still inside the TTL, so the cancel really is the reason
    /// the order closed.
    func testClosureBeforeExpiryWithACancelOnRecordIsCancelled() {
        let order = makeOrder(cancelBroadcastHash: "CANCELTX", blocksToExpiry: 10)
        let beforeExpiry = Self.observedAt.addingTimeInterval(30)

        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .refunded, with: order, now: beforeExpiry),
            .cancelled
        )
    }

    /// No cancel on record and an elapsed TTL: nothing to reinterpret, and
    /// nothing that could be asserted about the cause anyway.
    func testClosureAfterExpiryWithoutACancelStaysRefunded() {
        let order = makeOrder(blocksToExpiry: 10)
        let afterExpiry = Self.observedAt.addingTimeInterval(600)

        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .refunded, with: order, now: afterExpiry),
            .refunded
        )
    }

    /// With no anchored countdown the nominal `createdAt + TTL` deadline rules
    /// expiry out instead. Without it, an ineffective cancel followed by a
    /// natural expiry would report a successful cancellation — the same
    /// false-success the intent-record design exists to prevent, reached by a
    /// different route.
    func testAnUnobservedExpiryFallsBackToTheNominalDeadline() {
        // 14,400 blocks x 6s = 24h from `createdAt`.
        let order = makeOrder(cancelBroadcastHash: "CANCELTX")
        let wellPastNominalTTL = order.createdAt.addingTimeInterval(25 * 3600)

        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .refunded, with: order, now: wellPastNominalTTL),
            .refunded
        )
    }

    func testAnUnobservedExpiryStillAllowsCancelAttributionInsideTheTTL() {
        let order = makeOrder(cancelBroadcastHash: "CANCELTX")
        let wellInsideTTL = order.createdAt.addingTimeInterval(60)

        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .refunded, with: order, now: wellInsideTTL),
            .cancelled
        )
        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .refunded, with: makeOrder(), now: wellInsideTTL),
            .refunded
        )
    }

    /// The tracker can observe the closure BEFORE the done screen records the
    /// broadcast — a force-quit or a backgrounded app between signing and the
    /// done screen is enough. Refusing to record onto `.refunded` would drop the
    /// hash and leave a successful cancel reading "Refunded" forever.
    func testABroadcastRecordedAfterTheClosureWasAlreadyObservedStillReconciles() throws {
        let vault = Vault.example
        let order = makeOrder(status: .refunded)
        vault.limitOrders = [order]

        try LimitOrderStorageService().recordCancelBroadcast(
            of: "order-1", txHash: "CANCELTX", in: vault
        )

        XCTAssertEqual(order.cancelBroadcastHash, "CANCELTX")
        XCTAssertEqual(order.status, .cancelled)
    }

    /// …but only inside the TTL. Past it the cause is unknowable, whichever
    /// order the two writes happen to land in.
    func testALateBroadcastRecordDoesNotClaimAnAmbiguousClosure() throws {
        let vault = Vault.example
        let order = makeOrder(status: .refunded)
        order.createdAt = Date(timeIntervalSince1970: 0)
        vault.limitOrders = [order]

        try LimitOrderStorageService().recordCancelBroadcast(
            of: "order-1", txHash: "CANCELTX", in: vault
        )

        XCTAssertEqual(order.status, .refunded)
    }

    /// A fill is never reinterpreted, whatever else is true of the order.
    func testFillBeatsAnElapsedTTL() {
        let order = makeOrder(cancelBroadcastHash: "CANCELTX", blocksToExpiry: 10)
        let afterExpiry = Self.observedAt.addingTimeInterval(600)

        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .filled, with: order, now: afterExpiry),
            .filled
        )
    }

    func testOtherOutcomesPassThroughUnchanged() {
        let order = makeOrder(cancelBroadcastHash: "CANCELTX")

        XCTAssertEqual(LimitOrderStorageService.reconcile(observed: .expired, with: order), .expired)
        XCTAssertEqual(LimitOrderStorageService.reconcile(observed: .cancelled, with: order), .cancelled)
    }

    // MARK: - `.cancelling` — our transaction, not the order's fate

    /// The order is still in the queue and this device has a cancel confirmed
    /// on-chain against it. That is worth showing — and it is a statement about
    /// the TRANSACTION, so it must not be terminal.
    func testARestingOrderWithAConfirmedCancelBecomesCancelling() {
        let order = makeOrder(cancelBroadcastHash: "CANCELTX")

        XCTAssertEqual(LimitOrderStorageService.reconcile(observed: .pending, with: order), .cancelling)
    }

    /// Without a cancel of our own there is nothing to say.
    func testARestingOrderWithoutACancelStaysPending() {
        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .pending, with: makeOrder()),
            .pending
        )
    }

    /// ⚠️ The inviolable property. `.cancelling` describes our transaction, so it
    /// must keep the order in every resting surface: still tracked, still able
    /// to fill, still counting down. The moment it reads as terminal it is the
    /// false success this feature exists to prevent.
    func testCancellingIsNotTerminal() {
        XCTAssertFalse(makeOrder(status: .cancelling).details.isTerminal)
        XCTAssertFalse(THORChainLimitTrackingStatusMapper.map(.cancelling).isTerminal)
    }

    /// A cancelling order that FILLS filled. The cancel simply lost the race,
    /// and saying otherwise would misreport where the funds went.
    func testACancellingOrderThatFillsIsReportedAsFilled() {
        let order = makeOrder(status: .cancelling, cancelBroadcastHash: "CANCELTX", blocksToExpiry: 10)

        XCTAssertEqual(
            LimitOrderStorageService.reconcile(observed: .filled, with: order, now: Self.observedAt),
            .filled
        )
    }

    /// A cancelling order that leaves the queue past its TTL is ambiguous, and
    /// ambiguity never credits the cancel — same rule as a `.pending` one.
    func testACancellingOrderClosingPastItsTTLIsStillOnlyRefunded() {
        let order = makeOrder(status: .cancelling, cancelBroadcastHash: "CANCELTX", blocksToExpiry: 10)

        XCTAssertEqual(
            LimitOrderStorageService.reconcile(
                observed: .refunded,
                with: order,
                now: Self.observedAt.addingTimeInterval(600)
            ),
            .refunded
        )
    }

    /// ⚠️ Forward compatibility. A build that predates `.cancelling` reads the
    /// stored string through `LimitOrderStatus(rawValue:) ?? .pending`, so an
    /// unrecognised status degrades to a live, still-polled order — never to a
    /// terminal one it would never revisit.
    func testAnUnrecognisedStoredStatusDegradesToPendingRatherThanTerminal() {
        let order = makeOrder()
        order.statusRawValue = "someStatusThisBuildHasNeverHeardOf"

        XCTAssertEqual(order.status, .pending)
        XCTAssertFalse(order.details.isTerminal)
        XCTAssertFalse(
            THORChainLimitTrackingStatusMapper.map(trackingStatus: "someStatusThisBuildHasNeverHeardOf").isTerminal
        )
    }

    // MARK: - Broadcast recording

    /// Recording a confirmed cancel must NOT mark the order cancelled. A cancel
    /// that addresses the wrong ratio bucket is accepted, costs a fee, and
    /// cancels nothing; marking it cancelled here would hide exactly that
    /// failure. `.cancelling` acknowledges the transaction and nothing more —
    /// and stays non-terminal, so the order remains visibly resting.
    func testRecordingABroadcastLeavesTheOrderRestingRatherThanCancelled() throws {
        let vault = Vault.example
        let order = makeOrder()
        vault.limitOrders = [order]

        try LimitOrderStorageService().recordCancelBroadcast(
            of: "order-1", txHash: "CANCELTX", in: vault
        )

        XCTAssertEqual(order.cancelBroadcastHash, "CANCELTX")
        XCTAssertEqual(order.status, .cancelling, "a confirmed cancel tx is not a closed order")
        XCTAssertFalse(order.details.isTerminal)
    }

    /// The order can fill or expire between the tap and the ceremony finishing.
    /// A blind write would resurrect a terminal order.
    /// `.refunded` is deliberately absent — it IS accepted, and reconciled on
    /// the spot (see the race tests above). These three are outcomes the cancel
    /// demonstrably did not cause.
    func testRecordingABroadcastLeavesAnAlreadyTerminalOrderUntouched() throws {
        for status in [LimitOrderStatus.filled, .expired, .cancelled] {
            let vault = Vault.example
            let order = makeOrder(status: status)
            vault.limitOrders = [order]

            try LimitOrderStorageService().recordCancelBroadcast(
                of: "order-1", txHash: "CANCELTX", in: vault
            )

            XCTAssertEqual(order.status, status, "\(status) must survive")
            XCTAssertNil(order.cancelBroadcastHash, "\(status) must not gain a cancel record")
        }
    }

    // MARK: - Withdrawing a record whose transaction failed

    /// ⚠️ The self-heal. The 2026-07-21 rehearsal's cancel was recorded on its
    /// broadcast hash and then REFUSED by the chain — which greys the button out
    /// for good on an order that is still resting. Withdrawing the record is
    /// what makes it retryable.
    func testClearingACancelRecordReEnablesCancelling() throws {
        let vault = Vault.example
        let order = makeOrder(cancelBroadcastHash: "CANCELTX")
        vault.limitOrders = [order]

        try LimitOrderStorageService().clearCancelBroadcast(
            of: "order-1", expecting: "CANCELTX", in: vault
        )

        XCTAssertNil(order.cancelBroadcastHash)
        XCTAssertEqual(order.status, .pending, "still resting, and cancellable again")
    }

    /// The same self-heal seen through the visible state: a `.cancelling` order
    /// whose transaction turns out to have failed drops back to `.pending`, with
    /// its Cancel button live again. The label is only ever derived from the
    /// record, so withdrawing the record has to take it with it.
    func testClearingACancelRecordReturnsACancellingOrderToPending() throws {
        let vault = Vault.example
        let order = makeOrder(status: .cancelling, cancelBroadcastHash: "CANCELTX")
        vault.limitOrders = [order]

        try LimitOrderStorageService().clearCancelBroadcast(
            of: "order-1", expecting: "CANCELTX", in: vault
        )

        XCTAssertNil(order.cancelBroadcastHash)
        XCTAssertEqual(order.status, .pending)
    }

    /// ⚠️ Compare-and-set. The caller's verdict is seconds old by the time it
    /// lands, and a different hash stored since is a different cancel that the
    /// verdict says nothing about.
    func testClearingIsANoOpWhenADifferentCancelIsOnRecord() throws {
        let vault = Vault.example
        let order = makeOrder(cancelBroadcastHash: "NEWCANCEL")
        vault.limitOrders = [order]

        try LimitOrderStorageService().clearCancelBroadcast(
            of: "order-1", expecting: "OLDCANCEL", in: vault
        )

        XCTAssertEqual(order.cancelBroadcastHash, "NEWCANCEL")
    }

    /// A `.cancelled` label is only ever DERIVED from the record (see
    /// `reconcile`), so withdrawing the record has to take its conclusion with
    /// it — back to the observable fact.
    func testClearingACancelRecordRevertsACancelledLabelToRefunded() throws {
        let vault = Vault.example
        let order = makeOrder(status: .cancelled, cancelBroadcastHash: "CANCELTX")
        vault.limitOrders = [order]

        try LimitOrderStorageService().clearCancelBroadcast(
            of: "order-1", expecting: "CANCELTX", in: vault
        )

        XCTAssertEqual(order.status, .refunded)
        XCTAssertNil(order.cancelBroadcastHash)
    }

    /// Every other status is left exactly as it is — a fill is not a cancel
    /// gone wrong.
    func testClearingACancelRecordLeavesOtherStatusesAlone() throws {
        for status in [LimitOrderStatus.filled, .refunded, .expired] {
            let vault = Vault.example
            let order = makeOrder(status: status, cancelBroadcastHash: "CANCELTX")
            vault.limitOrders = [order]

            try LimitOrderStorageService().clearCancelBroadcast(
                of: "order-1", expecting: "CANCELTX", in: vault
            )

            XCTAssertEqual(order.status, status, "\(status) must survive")
        }
    }

    func testClearingAnOrderWithNoCancelRecordIsANoOp() throws {
        let vault = Vault.example
        let order = makeOrder()
        vault.limitOrders = [order]

        try LimitOrderStorageService().clearCancelBroadcast(
            of: "order-1", expecting: "CANCELTX", in: vault
        )

        XCTAssertNil(order.cancelBroadcastHash)
        XCTAssertEqual(order.status, .pending)
    }

    func testReadingBackTheRecordedCancelHash() throws {
        let vault = Vault.example
        let order = makeOrder(cancelBroadcastHash: "CANCELTX")
        vault.limitOrders = [order]

        XCTAssertEqual(
            LimitOrderStorageService().pendingCancelBroadcast(of: "order-1", in: vault),
            "CANCELTX"
        )
        XCTAssertNil(LimitOrderStorageService().pendingCancelBroadcast(of: "nope", in: vault))
    }

    func testRecordingABroadcastForAnUnknownOrderThrows() {
        let vault = Vault.example
        vault.limitOrders = []

        XCTAssertThrowsError(
            try LimitOrderStorageService().recordCancelBroadcast(
                of: "nope", txHash: "CANCELTX", in: vault
            )
        ) { error in
            XCTAssertEqual(error as? LimitOrderStorageError, .notFound(id: "nope"))
        }
    }
}
