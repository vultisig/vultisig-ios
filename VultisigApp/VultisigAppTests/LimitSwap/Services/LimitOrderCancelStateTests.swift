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
        XCTAssertEqual(LimitOrderStorageService.reconcile(observed: .pending, with: order), .pending)
    }

    // MARK: - Broadcast recording

    /// Broadcasting a cancel must NOT mark the order cancelled. A cancel that
    /// addresses the wrong ratio bucket is accepted, costs a fee, and cancels
    /// nothing; marking it cancelled here would hide exactly that failure.
    func testRecordingABroadcastLeavesTheOrderRestingRatherThanCancelled() throws {
        let vault = Vault.example
        let order = makeOrder()
        vault.limitOrders = [order]

        try LimitOrderStorageService().recordCancelBroadcast(
            of: "order-1", txHash: "CANCELTX", in: vault
        )

        XCTAssertEqual(order.cancelBroadcastHash, "CANCELTX")
        XCTAssertEqual(order.status, .pending, "a broadcast cancel is an intent, not an outcome")
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
