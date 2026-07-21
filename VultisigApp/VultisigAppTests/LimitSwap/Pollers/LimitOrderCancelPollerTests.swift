//
//  LimitOrderCancelPollerTests.swift
//  VultisigAppTests
//
//  The done screen's half of the fix: a cancel is credited to its order only
//  once the transaction carrying it is confirmed SUCCESSFUL on-chain.
//
//  Before this, the record was written from `onAppear` on the strength of a
//  non-empty broadcast hash. The 2026-07-21 mainnet rehearsal produced such a
//  hash for a cancel THORChain then REFUSED — so the app recorded a cancellation
//  that never happened, greyed the button out permanently on an order that was
//  still resting, and armed its eventual closure to be labelled "Cancelled".
//

import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrderCancelPollerTests: XCTestCase {

    /// The done screen opens on "broadcasted" — the ceremony finished, the chain
    /// has not answered yet. It must never open on success.
    func testItStartsOnBroadcastedNotConfirmed() {
        let (poller, _) = makePoller(outcome: .succeeded)

        XCTAssertNotEqual(poller.initialStatus, .confirmed)
        guard case .broadcasted = poller.initialStatus else {
            return XCTFail("expected broadcasted, got \(poller.initialStatus)")
        }
    }

    func testAConfirmedCancelIsRecordedAgainstItsOrder() async {
        let (poller, intents) = makePoller(outcome: .succeeded)

        let status = await firstStatus(from: poller)

        XCTAssertEqual(status, .confirmed)
        XCTAssertEqual(intents.recorded.map(\.inboundTxHash), ["ORDERHASH"])
        XCTAssertEqual(intents.recorded.map(\.txHash), ["CANCELTX"])
    }

    /// An L1 cancel can only ever be `.delivered` — THORChain's verdict on it is
    /// not observable — and that is still recorded, because it is the strongest
    /// evidence that route produces. The guard against over-claiming lives
    /// downstream, in `reconcile`'s TTL rule.
    func testADeliveredL1CancelIsRecordedToo() async {
        let (poller, intents) = makePoller(outcome: .delivered)

        let status = await firstStatus(from: poller)

        XCTAssertEqual(status, .confirmed)
        XCTAssertEqual(intents.recorded.map(\.txHash), ["CANCELTX"])
    }

    /// ⚠️ The whole point. A refused cancel records NOTHING, so the order keeps
    /// its live Cancel button and its eventual closure is still just a refund.
    func testARefusedCancelRecordsNothingAndSurfacesTheChainsReason() async {
        let (poller, intents) = makePoller(
            outcome: .failed(reason: "could not find matching limit swap: internal error")
        )

        let status = await firstStatus(from: poller)

        XCTAssertEqual(status, .failed(reason: "could not find matching limit swap: internal error"))
        XCTAssertTrue(intents.recorded.isEmpty, "a refused cancel must leave no record behind")
    }

    /// A broadcast hash on its own is not evidence of anything, and the poller
    /// must not act on one while the chain has not answered.
    ///
    /// Waits on the verification actually happening rather than on a yield, so
    /// "nothing was recorded" is a real observation and not a race the test
    /// happened to win.
    func testAnUnresolvedLookupRecordsNothingYet() async {
        let intents = RecordingIntentStore()
        let asked = expectation(description: "the chain was asked")
        let poller = makePoller(
            verifier: StubVerifier(outcome: .unresolved, onVerify: { asked.fulfill() }),
            intents: intents
        )

        poller.start { _ in }
        await fulfillment(of: [asked], timeout: 2)
        poller.stop()

        XCTAssertTrue(intents.recorded.isEmpty)
    }

    /// A failed write is not worth an error over a cancel that already
    /// succeeded: the cost is the order later reading "Refunded" instead of
    /// "Cancelled" — the wrong label on the right outcome.
    func testAFailedRecordingStillReportsTheCancelConfirmed() async {
        let (poller, intents) = makePoller(outcome: .succeeded)
        intents.recordShouldThrow = true

        let status = await firstStatus(from: poller)

        XCTAssertEqual(status, .confirmed)
    }

    // MARK: - Helpers

    private func makePoller(
        outcome: LimitOrderCancelTxOutcome
    ) -> (LimitOrderCancelPoller, RecordingIntentStore) {
        let intents = RecordingIntentStore()
        return (makePoller(verifier: StubVerifier(outcome: outcome), intents: intents), intents)
    }

    private func makePoller(
        verifier: LimitOrderCancelVerifying,
        intents: LimitOrderCancelIntentStoring
    ) -> LimitOrderCancelPoller {
        LimitOrderCancelPoller(
            txHash: "CANCELTX",
            chain: .thorChain,
            request: LimitOrderCancelRequest(
                orderId: "ORDERHASH_vault-pub",
                inboundTxHash: "ORDERHASH",
                memo: "m=<:1THOR.RUNE:1BTC.BTC:0",
                sourceAsset: "THOR.RUNE",
                targetAsset: "BTC.BTC",
                sourceChainRawValue: Chain.thorChain.rawValue,
                duplicateRestingOrderCount: 0
            ),
            pubKeyECDSA: "vault-pub",
            verifier: verifier,
            intents: intents
        )
    }

    /// Runs the poller until it publishes its first status and then stops it.
    /// Every case under test resolves on the first round, so this never waits on
    /// the poll interval.
    private func firstStatus(from poller: LimitOrderCancelPoller) async -> TransactionStatus? {
        await withCheckedContinuation { continuation in
            let box = ResumeOnce(continuation)
            poller.start { status in box.resume(with: status) }
        }
    }
}

// MARK: - Doubles

/// A continuation must be resumed exactly once; the poller's callback is not
/// contractually single-shot.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<TransactionStatus?, Never>?

    init(_ continuation: CheckedContinuation<TransactionStatus?, Never>) {
        self.continuation = continuation
    }

    func resume(with status: TransactionStatus) {
        continuation?.resume(returning: status)
        continuation = nil
    }
}

@MainActor
private final class StubVerifier: LimitOrderCancelVerifying {
    private let outcome: LimitOrderCancelTxOutcome
    private let onVerify: (() -> Void)?

    init(outcome: LimitOrderCancelTxOutcome, onVerify: (() -> Void)? = nil) {
        self.outcome = outcome
        self.onVerify = onVerify
    }

    func verifyCancelTransaction(txHash _: String, chain _: Chain) async -> LimitOrderCancelTxOutcome { // swiftlint:disable:this async_without_await
        onVerify?()
        return outcome
    }
}

@MainActor
private final class RecordingIntentStore: LimitOrderCancelIntentStoring {
    private(set) var recorded: [(inboundTxHash: String, txHash: String)] = []
    var recordShouldThrow = false

    struct WriteError: Error {}

    func pendingCancelBroadcast(inboundTxHash _: String, pubKeyECDSA _: String) -> String? { nil }

    func recordCancelBroadcast(inboundTxHash: String, pubKeyECDSA _: String, txHash: String) throws {
        if recordShouldThrow { throw WriteError() }
        recorded.append((inboundTxHash, txHash))
    }

    func clearCancelBroadcast(inboundTxHash _: String, pubKeyECDSA _: String, expecting _: String) throws {}
}
