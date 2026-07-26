//
//  LimitOrderCancelPollerTests.swift
//  VultisigAppTests
//
//  The done screen's half of the state machine: the order enters `.cancelling`
//  the instant the cancel broadcasts, and the poller then withdraws that record
//  if the chain refuses the transaction.
//
//  Entry is on BROADCAST, not on the chain's answer — synchronously in `start()`,
//  before the poll task runs and before the user can tap Done — so a fast cancel
//  (worst on the L1 route) is observable at all. This is safe only because the
//  cancel hash no longer labels the CLOSURE: the terminal `.cancelled` label
//  comes from THORChain's own reason, so an optimistic hash yields the
//  non-terminal `.cancelling` and never a false "Cancelled". A cancel the chain
//  refuses — as the 2026-07-21 rehearsal's was — has its record withdrawn here,
//  returning the order to `.pending` with its Cancel button live again.
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

    /// ⚠️ The reversal. The order enters `.cancelling` the instant the cancel
    /// broadcasts — synchronously in `start()`, before the poll task runs and
    /// before the chain has answered. A verifier that never resolves proves the
    /// record does not wait on the chain's verdict.
    func testTheCancelIsRecordedImmediatelyOnBroadcast() {
        let intents = RecordingIntentStore()
        let poller = makePoller(verifier: StubVerifier(outcome: .unresolved), intents: intents)

        poller.start { _ in }
        // No await: the write is synchronous in `start()`.
        XCTAssertEqual(intents.recorded.map(\.inboundTxHash), ["ORDERHASH"])
        XCTAssertEqual(intents.recorded.map(\.txHash), ["CANCELTX"])
        // Recorded but NOT confirmed: the broadcast alone shows `.cancelling`,
        // never a terminal `.cancelled`. Confirmation waits for the chain.
        XCTAssertTrue(intents.confirmed.isEmpty)
        XCTAssertTrue(intents.cleared.isEmpty)
        poller.stop()
    }

    /// The chain accepting the cancel keeps the broadcast record, marks it
    /// CONFIRMED — which is what unlocks the terminal fallback — and settles the
    /// transaction's own header to confirmed.
    func testAConfirmedCancelIsRecordedThenConfirmedAndReportsConfirmed() async {
        let (poller, intents) = makePoller(outcome: .succeeded)

        let status = await firstStatus(from: poller)

        XCTAssertEqual(status, .confirmed)
        XCTAssertEqual(intents.recorded.map(\.txHash), ["CANCELTX"])
        XCTAssertEqual(intents.confirmed.map(\.txHash), ["CANCELTX"])
        XCTAssertTrue(intents.cleared.isEmpty)
    }

    /// An L1 cancel can only ever be `.delivered` — THORChain's verdict on it is
    /// not observable — and that counts as confirmation, because it is the
    /// strongest evidence that route produces. The guard against over-claiming
    /// lives downstream, in `reconcile`'s TTL rule.
    func testADeliveredL1CancelIsConfirmed() async {
        let (poller, intents) = makePoller(outcome: .delivered)

        let status = await firstStatus(from: poller)

        XCTAssertEqual(status, .confirmed)
        XCTAssertEqual(intents.recorded.map(\.txHash), ["CANCELTX"])
        XCTAssertEqual(intents.confirmed.map(\.txHash), ["CANCELTX"])
        XCTAssertTrue(intents.cleared.isEmpty)
    }

    /// ⚠️ The failure half. A cancel the chain refuses has its broadcast record
    /// WITHDRAWN — the order drops out of `.cancelling` back to `.pending`, its
    /// Cancel button live again — and the chain's own reason is surfaced.
    /// Withdrawing is compare-and-set on the exact hash that was recorded.
    func testARefusedCancelWithdrawsTheRecordAndSurfacesTheChainsReason() async {
        let (poller, intents) = makePoller(
            outcome: .failed(reason: "could not find matching limit swap: internal error")
        )

        let status = await firstStatus(from: poller)

        XCTAssertEqual(status, .failed(reason: "could not find matching limit swap: internal error"))
        // Recorded on broadcast, then withdrawn once the chain refused it, and
        // never confirmed.
        XCTAssertEqual(intents.recorded.map(\.txHash), ["CANCELTX"])
        XCTAssertTrue(intents.confirmed.isEmpty)
        XCTAssertEqual(intents.cleared.map(\.txHash), ["CANCELTX"])
    }

    /// While the chain has not answered, the broadcast record STANDS — the order
    /// stays `.cancelling`. Nothing is withdrawn until a refusal is actually read.
    ///
    /// Waits on the verification actually happening rather than on a yield, so
    /// "nothing was withdrawn" is a real observation and not a race the test
    /// happened to win.
    func testAnUnresolvedLookupLeavesTheBroadcastRecordStanding() async {
        let intents = RecordingIntentStore()
        let asked = expectation(description: "the chain was asked")
        let poller = makePoller(
            verifier: StubVerifier(outcome: .unresolved, onVerify: { asked.fulfill() }),
            intents: intents
        )

        poller.start { _ in }
        await fulfillment(of: [asked], timeout: 2)
        poller.stop()

        XCTAssertEqual(intents.recorded.map(\.txHash), ["CANCELTX"])
        // Neither confirmed nor withdrawn while the chain has not answered — the
        // order stays `.cancelling`, out of reach of the terminal fallback.
        XCTAssertTrue(intents.confirmed.isEmpty)
        XCTAssertTrue(intents.cleared.isEmpty)
    }

    /// A failed broadcast record-write is not worth an error over a transaction
    /// that went out: the poll still runs and the chain's acceptance still
    /// reports confirmed. The cost is only the order not showing "Cancelling…"
    /// until the tracker's next poll reconciles it.
    func testAFailedBroadcastRecordingStillReportsTheCancelConfirmed() async {
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
    private(set) var confirmed: [(inboundTxHash: String, txHash: String)] = []
    private(set) var cleared: [(inboundTxHash: String, txHash: String)] = []
    var recordShouldThrow = false

    struct WriteError: Error {}

    func pendingCancelBroadcast(inboundTxHash _: String, pubKeyECDSA _: String) -> String? { nil }

    func recordCancelBroadcast(inboundTxHash: String, pubKeyECDSA _: String, txHash: String) throws {
        if recordShouldThrow { throw WriteError() }
        recorded.append((inboundTxHash, txHash))
    }

    func confirmCancelBroadcast(inboundTxHash: String, pubKeyECDSA _: String, txHash: String) throws {
        confirmed.append((inboundTxHash, txHash))
    }

    func clearCancelBroadcast(inboundTxHash: String, pubKeyECDSA _: String, expecting txHash: String) throws {
        cleared.append((inboundTxHash, txHash))
    }
}
