//
//  THORChainLimitTrackingPollTests.swift
//  VultisigAppTests
//
//  Drives the limit tracker's state machine through its real transitions with
//  stubbed HTTP + collaborators, one cycle at a time so nothing sleeps.
//
//  The invariant under test throughout: an order is only ever declared terminal
//  on evidence. Every ambiguity — an unparseable queue, a network failure, a
//  response we don't recognise, an outcome Midgard hasn't indexed — must leave
//  it resting, because nothing revisits a terminal order.
//

import XCTest
@testable import VultisigApp

@MainActor
final class THORChainLimitTrackingPollTests: XCTestCase {

    private let sender = "thor1sender"

    // MARK: - Resting

    func testAnOrderStillInTheQueueIsRecordedAsResting() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .pending)
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertEqual(env.storage.mirroredTrackingStatuses.last, "pending")
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "still resting — keep tracking it")
    }

    /// ⚠️ The row mirrors the status the order table STORED, not the raw
    /// observation. A resting order with a confirmed cancel against it is
    /// reconciled to `.cancelling`; mirroring "pending" instead would leave the
    /// row and the authoritative table describing the same order differently,
    /// and the row's status is what the surfaces read after a relaunch.
    func testARestingOrderReconciledToCancellingIsMirroredAsCancelling() async {
        let env = TestEnv(
            queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"),
            pendingCancelHash: "CANCELTX",
            cancelOutcome: .succeeded
        )
        env.orders.effectiveStatus = .cancelling
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .pending, "the OBSERVATION is still 'in the queue'")
        XCTAssertEqual(env.storage.mirroredTrackingStatuses.last, "cancelling")
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .cancelling)
        XCTAssertEqual(
            env.service.trackedOrderCountForTesting,
            1,
            "cancelling is not terminal — the order is still resting and must keep being polled"
        )
    }

    /// The queue is polled ONCE per sender, not once per order — that's the
    /// whole reason for the list endpoint.
    func testOneRequestCoversEveryOrderForASender() async {
        let env = TestEnv(queueBody: .restingMany(hashes: ["ABC123", "DEF456"]))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        env.service.start(tx: env.makeRow(txHash: "DEF456"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.http.requestCount, 1, "two orders, one sender, one request")
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertEqual(env.service.uiStatusByTxHash["DEF456"], .resting)
    }

    func testTheFillSplitIsRecordedFromTheQueue() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "400", outAmount: "25"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        let observation = env.orders.observations.last
        XCTAssertEqual(observation?.depositAmount, "1000")
        XCTAssertEqual(observation?.filledInAmount, "400")
        XCTAssertEqual(observation?.filledOutAmount, "25")
    }

    /// ⚠️ The assets THORChain resolved the order to are recorded on every
    /// resting poll. They are the ONLY way to recover the full contract address
    /// a cancel memo has to spell out — the placement memo's abbreviation is
    /// not reversible — and so the only thing that makes an order placed before
    /// that was recorded locally cancellable at all.
    func testTheResolvedAssetsAreRecordedFromTheQueue() async {
        let env = TestEnv(queueBody: .restingWithResolvedAssets(hash: "ABC123"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        let observation = env.orders.observations.last
        XCTAssertEqual(observation?.observedSourceAsset, "THOR.RUNE")
        XCTAssertEqual(observation?.observedTargetAsset, "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")
    }

    /// Most entries carry no assets we can read, and that is not an error: `nil`
    /// means "not observed" and must leave any stored value alone.
    func testAbsentAssetsAreRecordedAsNotObserved() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertNil(env.orders.observations.last?.observedSourceAsset)
        XCTAssertNil(env.orders.observations.last?.observedTargetAsset)
    }

    // MARK: - Self-healing a cancel record whose transaction failed

    /// ⚠️ The repair for the 2026-07-21 rehearsal. That cancel was included in a
    /// block and REFUSED by the handler, but the app had already recorded it —
    /// which greys the Cancel button out for good on an order that is still
    /// resting, and leaves the eventual closure ready to be labelled
    /// "Cancelled". Seeing the order still in the queue is exactly the moment to
    /// re-check the transaction and withdraw the record.
    func testACancelRecordWhoseTransactionFailedIsWithdrawn() async {
        let env = TestEnv(
            queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"),
            pendingCancelHash: "CANCELTX",
            cancelOutcome: .failed(reason: "could not find matching limit swap: internal error")
        )
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.cancelIntents.clearedHashes, ["ABC123"])
        XCTAssertNil(env.cancelIntents.pending, "a refused cancel must not keep the button disabled")
    }

    /// ⚠️ Order matters. The resting observation is reconciled against the cancel
    /// record — a present hash is what makes a resting order read
    /// "Cancelling…" — so it has to be recorded AFTER the record has been
    /// re-checked. The other way round persists and mirrors `.cancelling` on the
    /// strength of a hash the same cycle then withdraws, leaving the row
    /// contradicting the order it mirrors until the next poll repairs it.
    func testTheCancelRecordIsReCheckedBeforeTheRestingObservationIsRecorded() async {
        let env = TestEnv(
            queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"),
            pendingCancelHash: "CANCELTX",
            cancelOutcome: .failed(reason: "could not find matching limit swap: internal error")
        )
        var observationsAtVerifyTime: Int?
        env.cancelVerifier.onVerify = { observationsAtVerifyTime = env.orders.observations.count }
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(observationsAtVerifyTime, 0, "the record is verified before anything is written")
        XCTAssertEqual(env.orders.observations.count, 1, "and the observation still lands")
    }

    /// A cancel the chain accepted stays on record — it is what turns the
    /// eventual closure into "Cancelled" rather than "Refunded".
    func testASuccessfulCancelRecordIsKept() async {
        let env = TestEnv(
            queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"),
            pendingCancelHash: "CANCELTX",
            cancelOutcome: .succeeded
        )
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertTrue(env.cancelIntents.clearedHashes.isEmpty)
        XCTAssertEqual(env.cancelIntents.pending, "CANCELTX")
    }

    /// …and is not re-checked on every subsequent poll. The order can rest for
    /// blocks after a successful cancel; asking the chain the same settled
    /// question once a minute is pure noise.
    func testAVerifiedCancelIsNotReCheckedOnLaterPolls() async {
        let env = TestEnv(
            queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"),
            pendingCancelHash: "CANCELTX",
            cancelOutcome: .succeeded
        )
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)
        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.cancelVerifier.verifyCount, 1)
    }

    /// ⚠️ Compare-and-set. The verification is a network round-trip, so its
    /// verdict is seconds old by the time it lands; a DIFFERENT cancel recorded
    /// in the meantime is a different transaction the old verdict says nothing
    /// about, and withdrawing it would unblock a cancel that is genuinely in
    /// flight.
    func testAFailedVerdictDoesNotWithdrawADifferentCancelRecordedSince() async {
        let env = TestEnv(
            queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"),
            pendingCancelHash: "OLDCANCEL",
            cancelOutcome: .failed(reason: "could not find matching limit swap: internal error")
        )
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        // The substitution happens DURING the lookup — which is the whole race.
        // Recording it beforehand would just be verifying the newer hash.
        env.cancelVerifier.onVerify = { [intents = env.cancelIntents] in
            try? intents.recordCancelBroadcast(
                inboundTxHash: "ABC123", pubKeyECDSA: "vault-pub", txHash: "NEWCANCEL"
            )
        }

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.cancelIntents.pending, "NEWCANCEL", "the newer cancel survives")
        XCTAssertTrue(env.cancelIntents.clearedHashes.isEmpty)
    }

    /// ⚠️ An unanswerable lookup is not a failure. Withdrawing the record on a
    /// rate limit or an unindexed transaction would re-enable the button on an
    /// order that IS being cancelled, and invite the user to pay a second fee.
    func testAnUnresolvedLookupLeavesTheCancelRecordAlone() async {
        let env = TestEnv(
            queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"),
            pendingCancelHash: "CANCELTX",
            cancelOutcome: .unresolved
        )
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertTrue(env.cancelIntents.clearedHashes.isEmpty)
        XCTAssertEqual(env.cancelIntents.pending, "CANCELTX")
        // Still unsettled, so the next poll must ask again.
        await env.service.pollOnceForTesting(sender: sender)
        XCTAssertEqual(env.cancelVerifier.verifyCount, 2)
    }

    /// Orders with no cancel on record cost nothing — the vast majority.
    func testNoCancelRecordMeansNoLookupAtAll() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.cancelVerifier.verifyCount, 0)
    }

    /// A CLOSED order's record is left alone. By then it has already done its
    /// work — `reconcile` read it to tell a cancellation from a plain refund —
    /// and withdrawing it would rewrite settled history from a lookup that may
    /// simply have been rate-limited.
    func testAClosedOrdersCancelRecordIsNotReExamined() async {
        let env = TestEnv(
            queueBody: .empty,
            outcome: .refunded,
            pendingCancelHash: "CANCELTX",
            cancelOutcome: .failed(reason: "whatever")
        )
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.cancelVerifier.verifyCount, 0)
        XCTAssertTrue(env.cancelIntents.clearedHashes.isEmpty)
    }

    /// The expiry countdown is persisted alongside the split. Without it the
    /// detail sheet has no honest way to say how long an order has left — the
    /// stored TTL is a guess that assumes the deposit queued the instant it was
    /// signed and that blocks are exactly 6s.
    func testTheExpiryCountdownIsRecordedFromTheQueue() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        // Base 10. Caught a real one: an unapplied `Int.init` resolves to this
        // codebase's `Int.init?(hex:)` extension, so `flatMap(Int.init)` parsed
        // "39069" as base-16 (= 233577) and the chip would have promised ~6x
        // the time the order actually had left.
        XCTAssertEqual(env.orders.observations.last?.timeToExpiryBlocks, 39069)
    }

    /// The queue reports every number as a string, and nothing guarantees it
    /// parses. A dropped countdown just hides the chip; a defaulted `0` would
    /// tell the user a healthy resting order had expired.
    func testAnUnparseableExpiryCountdownIsDroppedRatherThanDefaultedToZero() async {
        let env = TestEnv(queueBody: .restingWithExpiry(hash: "ABC123", expiryBlocks: "not-a-number"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        let observation = env.orders.observations.last
        XCTAssertEqual(observation?.status, .pending, "It's still resting — the countdown just didn't parse")
        XCTAssertNil(observation?.timeToExpiryBlocks)
    }

    /// The key is optional on the wire.
    func testAMissingExpiryCountdownIsNotAnError() async {
        let env = TestEnv(queueBody: .restingMany(hashes: ["ABC123"]))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertNil(env.orders.observations.last?.timeToExpiryBlocks)
    }

    /// A terminal order is already gone from the queue, so there is no
    /// countdown left to report — and overwriting the last known split with
    /// "unknown" would lose the only record of how much of it filled.
    func testATerminalWriteLeavesTheSplitAndExpiryUntouched() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        let observation = env.orders.observations.last
        XCTAssertEqual(observation?.status, .filled)
        XCTAssertNil(observation?.timeToExpiryBlocks, "A closed order has no countdown")
        XCTAssertNil(observation?.depositAmount, "nil means 'not observed' and must not clobber the stored split")
    }

    /// A partially-filled order is still resting — the remainder is genuinely
    /// still working.
    func testAPartiallyFilledOrderStaysResting() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "400", outAmount: "25"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertFalse(env.service.uiStatusByTxHash["ABC123"]!.isTerminal)
    }

    /// The queue's hash casing needn't match what we broadcast under; hex case
    /// carries no meaning and must not make an order look closed.
    func testHashMatchingIsCaseInsensitive() async {
        let env = TestEnv(queueBody: .resting(hash: "abc123", deposit: "1000", inAmount: "0", outAmount: "0"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertEqual(env.outcomes.resolveCount, 0, "must not be treated as closed")
    }

    /// A poll is scoped to ONE sender's queue, so it must not reason about
    /// another address's orders — their absence from this response says nothing
    /// about them. (`start` seeds a UI status for any row it takes up; what must
    /// not happen is an observation or an outcome lookup.)
    func testAPollDoesNotReasonAboutAnotherSendersOrders() async {
        let env = TestEnv(queueBody: .empty)
        env.service.start(tx: env.makeRow(txHash: "OTHER1", fromAddress: "thor1elsewhere"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertTrue(env.orders.observations.isEmpty, "another sender's order must not be written")
        XCTAssertEqual(env.outcomes.resolveCount, 0, "absence from this sender's queue proves nothing about it")
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "and it must stay tracked")
    }

    // MARK: - Disappearance → terminal, on evidence

    func testAnOrderThatLeavesTheQueueAndFilledIsCompleted() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .filled)
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .completed)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0, "terminal — stop tracking")
    }

    /// Recorded as REFUNDED, not expired. The funds coming back is what we
    /// observed; "your order expired" is a cause we can't corroborate, and it
    /// would be a fabricated explanation for an order rejected at placement.
    func testAnOrderThatLeavesTheQueueAndRefundedIsRecordedAsRefunded() async {
        let env = TestEnv(queueBody: .empty, outcome: .refunded)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .refunded)
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .refunded)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0)
    }

    /// Terminal writes carry no amounts, so the last resting observation — the
    /// final word on how much filled — survives the order leaving the queue.
    func testATerminalWriteDoesNotOverwriteTheLastKnownSplit() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "400", outAmount: "25"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        await env.service.pollOnceForTesting(sender: sender)

        env.http.body = QueueBody.empty.json
        env.outcomes.outcome = .refunded
        await env.service.pollOnceForTesting(sender: sender)

        let terminal = env.orders.observations.last
        XCTAssertEqual(terminal?.status, .refunded)
        XCTAssertNil(terminal?.depositAmount, "nil leaves the stored split alone")
        XCTAssertNil(terminal?.filledInAmount)
        XCTAssertNil(terminal?.filledOutAmount)
    }

    // MARK: - Ambiguity must never close an order

    /// Gone from the queue but Midgard hasn't indexed it yet: we know it closed
    /// but not how. Guessing would be permanent.
    func testAnUnresolvableOutcomeLeavesTheOrderRestingAndTracked() async {
        let env = TestEnv(queueBody: .empty, outcome: .unresolved)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertNotEqual(env.orders.observations.last?.status, .refunded)
        XCTAssertNotEqual(env.orders.observations.last?.status, .filled)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "keep asking until it answers")
    }

    /// An unresolved order resolves on a later poll, once indexing catches up.
    func testAnUnresolvedOrderIsResolvedOnALaterPoll() async {
        let env = TestEnv(queueBody: .empty, outcome: .unresolved)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        await env.service.pollOnceForTesting(sender: sender)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1)

        env.outcomes.outcome = .filled
        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .completed)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0)
    }

    /// The `limit_swaps` key absent is a response we don't understand — NOT an
    /// empty queue. Reading it as empty would close every order at once.
    func testAnUnrecognisedQueueEnvelopeDoesNotCloseOrders() async {
        let env = TestEnv(queueBody: .unrecognisedEnvelope, outcome: .refunded)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.outcomes.resolveCount, 0, "must not even ask — we don't know it closed")
        XCTAssertTrue(env.orders.observations.isEmpty)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1)
    }

    func testANetworkFailureDoesNotCloseOrders() async {
        let env = TestEnv(queueBody: .empty, outcome: .refunded)
        env.http.shouldThrow = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.outcomes.resolveCount, 0)
        XCTAssertTrue(env.orders.observations.isEmpty)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1)
    }

    /// The tracker must never write `unknownPendingExtended`: that flag hands
    /// authority back to the native poller, which would confirm the deposit and
    /// report a resting order Successful — the original bug.
    func testTheTrackerNeverSurrendersToNativePolling() async {
        let env = TestEnv(queueBody: .empty, outcome: .refunded)
        env.http.shouldThrow = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)
        await env.service.pollOnceForTesting(sender: sender)
        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertFalse(
            env.storage.observedUiStatuses.contains(.unknownPendingExtended),
            "an outage must never hand a limit row back to native polling"
        )
    }

    /// If the authoritative write fails, the order must stay tracked. Releasing
    /// it would leave `LimitOrder` permanently non-terminal with nothing left to
    /// correct it, while the row had already moved on — the two tables
    /// disagreeing forever.
    func testAnOrderIsNotReleasedWhenTheAuthoritativeWriteFails() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.orders.shouldThrow = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "keep it, so a later poll can retry the write")
    }

    /// An observer that can't resolve the vault must FAIL, not return quietly.
    /// Returning normally would report success for a write that never happened,
    /// and the order would be released with `LimitOrder` never updated.
    func testAVaultThatCannotBeResolvedFailsTheWriteRatherThanReleasing() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.orders.error = LimitOrderObservingError.vaultUnavailable(pubKeyECDSA: "vault-pub")
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1)
    }

    /// On a CO-SIGNER there is no local `LimitOrder` behind the row, so the row
    /// mirror is not a mirror at all — it is the only terminal state this device
    /// will ever persist. If it fails, the order must stay tracked: releasing it
    /// would strand the row non-terminal for the rest of the session with
    /// nothing left to correct it.
    func testACoSignerOrderIsNotReleasedWhenTheRowWriteFails() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.orders.error = LimitOrderStorageError.notFound(id: "ABC123_vault-pub")
        env.storage.shouldThrowOnUpdate = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(
            env.service.trackedOrderCountForTesting,
            1,
            "keep it, so a later poll can retry the only write this device has"
        )
    }

    /// The counterpart: with the row write landing, a co-signer's order IS
    /// terminal and must still be released. Holding it open on the strength of
    /// a missing local order would peg the row at "resting" for good — the very
    /// thing the `notFound` branch exists to prevent.
    func testACoSignerOrderIsReleasedOnceTheRowWriteLands() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.orders.error = LimitOrderStorageError.notFound(id: "ABC123_vault-pub")
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.storage.observedUiStatuses.last, .completed, "the row is the whole picture here")
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0, "terminal — stop tracking")
    }

    /// A later poll completes the write that previously failed.
    func testAFailedTerminalWriteIsRetriedOnALaterPoll() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.orders.shouldThrow = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        await env.service.pollOnceForTesting(sender: sender)

        env.orders.shouldThrow = false
        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .filled)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0)
    }

    // MARK: - Tracking preconditions

    /// Without a sender the queue can't be scoped, and an unscoped request
    /// returns the whole network's queue.
    func testARowWithoutASenderIsNotTracked() {
        // Scheduled, so the "no poll started" assertion is meaningful rather
        // than trivially true.
        let env = TestEnv(queueBody: .empty, scheduled: true)

        env.service.start(tx: env.makeRow(txHash: "ABC123", fromAddress: ""))

        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0)
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 0)
    }

    func testStoppingTheLastOrderForASenderEndsItsPoll() {
        let env = TestEnv(queueBody: .empty, scheduled: true)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 1)

        env.service.stop(txHash: "ABC123")

        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 0)
    }

    /// Two orders from the same address share ONE poll loop — the queue is
    /// scoped per sender, which is the whole reason for the list endpoint.
    func testOrdersFromOneSenderShareASinglePollLoop() {
        let env = TestEnv(queueBody: .empty, scheduled: true)

        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        env.service.start(tx: env.makeRow(txHash: "DEF456"))

        XCTAssertEqual(env.service.trackedOrderCountForTesting, 2)
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 1)
    }

    func testBackgroundingCancelsPollsAndForegroundingResumesThem() {
        let env = TestEnv(queueBody: .empty, scheduled: true)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        env.service.setActive(false)
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 0)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "still tracked, just not polling")

        env.service.setActive(true)
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 1)
    }
}

// MARK: - Test environment

@MainActor
private struct TestEnv {
    let http: StubQueueHTTPClient
    let storage: RecordingTrackingStorage
    let orders: RecordingLimitOrderObserver
    let outcomes: StubOutcomeResolver
    let cancelIntents: RecordingCancelIntentStore
    let cancelVerifier: StubCancelVerifier
    let service: THORChainLimitTrackingService

    /// - Parameter scheduled: leave `false` (the default) to suppress the
    ///   background poll loop `start` would otherwise kick off, so each test
    ///   drives cycles itself via `pollOnceForTesting` and asserts on exactly
    ///   the requests it caused. Pass `true` only to exercise scheduling.
    init(
        queueBody: QueueBody,
        outcome: LimitOrderOutcome = .unresolved,
        scheduled: Bool = false,
        pendingCancelHash: String? = nil,
        cancelOutcome: LimitOrderCancelTxOutcome = .unresolved
    ) {
        http = StubQueueHTTPClient(body: queueBody.json)
        storage = RecordingTrackingStorage()
        orders = RecordingLimitOrderObserver()
        outcomes = StubOutcomeResolver(outcome: outcome)
        cancelIntents = RecordingCancelIntentStore(pending: pendingCancelHash)
        cancelVerifier = StubCancelVerifier(outcome: cancelOutcome)
        service = THORChainLimitTrackingService(
            httpClient: http,
            storage: storage,
            orders: orders,
            outcomes: outcomes,
            cancelIntents: cancelIntents,
            cancelVerifier: cancelVerifier
        )
        if !scheduled {
            service.setActive(false)
        }
    }

    func makeRow(txHash: String, fromAddress: String = "thor1sender") -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .swap,
            status: .inProgress,
            chainRawValue: Chain.thorChain.rawValue,
            coinTicker: "RUNE",
            coinLogo: "rune",
            coinChainLogo: nil,
            amountCrypto: "600.12",
            amountFiat: "1000",
            fromAddress: fromAddress,
            toAddress: "bc1qto",
            toCoinTicker: "BTC",
            toCoinLogo: "btc",
            toCoinChainLogo: nil,
            toAmountCrypto: "0.0125",
            toAmountFiat: "1000",
            swapProvider: "THORChain",
            feeCrypto: "0.02",
            feeFiat: "0.04",
            network: "THORChain",
            explorerLink: "https://runescan.io/tx/\(txHash)",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: THORChainLimitTrackingService.metadata(
                broadcastHash: txHash,
                sourceChain: .thorChain
            )
        )
    }
}

private enum QueueBody {
    case empty
    case resting(hash: String, deposit: String, inAmount: String, outAmount: String)
    case restingMany(hashes: [String])
    /// A resting order with a specific (possibly junk) expiry countdown.
    case restingWithExpiry(hash: String, expiryBlocks: String)
    /// A 200 whose `limit_swaps` key is absent.
    case unrecognisedEnvelope
    /// A resting order carrying the assets THORChain resolved it to — the
    /// placement memo's `ETH.USDC-06EB48` expanded to its full contract.
    case restingWithResolvedAssets(hash: String)

    var json: String {
        switch self {
        case .empty:
            return #"{"limit_swaps":[]}"#
        case let .restingWithResolvedAssets(hash):
            return """
            {"limit_swaps":[{"time_to_expiry_blocks":"39069",
              "swap":{"tx":{"id":"\(hash)","from_address":"thor1sender",
                            "coins":[{"asset":"THOR.RUNE","amount":"370939666"}]},
                      "target_asset":"ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                      "trade_target":"167889485",
                      "state":{"deposit":"370939666","in":"0","out":"0","failed_swap_reasons":[]}}}]}
            """
        case let .restingWithExpiry(hash, expiryBlocks):
            return """
            {"limit_swaps":[{"time_to_expiry_blocks":"\(expiryBlocks)",
              "swap":{"tx":{"id":"\(hash)","from_address":"thor1sender"},
                      "state":{"deposit":"1000","in":"0","out":"0","failed_swap_reasons":[]}}}]}
            """
        case let .resting(hash, deposit, inAmount, outAmount):
            return """
            {"limit_swaps":[{"time_to_expiry_blocks":"39069",
              "swap":{"tx":{"id":"\(hash)","from_address":"thor1sender"},
                      "state":{"deposit":"\(deposit)","in":"\(inAmount)","out":"\(outAmount)","failed_swap_reasons":[]}}}]}
            """
        case let .restingMany(hashes):
            let entries = hashes.map {
                """
                {"swap":{"tx":{"id":"\($0)"},"state":{"deposit":"1000","in":"0","out":"0"}}}
                """
            }.joined(separator: ",")
            return #"{"limit_swaps":[\#(entries)]}"#
        case .unrecognisedEnvelope:
            return #"{"some_other_envelope":"we have never seen this"}"#
        }
    }
}

// MARK: - Fakes

private final class StubQueueHTTPClient: HTTPClientProtocol {
    var body: String
    var shouldThrow = false
    private(set) var requestCount = 0

    struct StubError: Error {}

    init(body: String) {
        self.body = body
    }

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        requestCount += 1
        if shouldThrow { throw StubError() }
        let url = URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    func requestEmpty(_ target: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        _ = try await request(target)
        let url = URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: EmptyResponse(), response: response)
    }
}

@MainActor
private final class RecordingLimitOrderObserver: LimitOrderObserving {
    struct Observation {
        let inboundTxHash: String
        let status: LimitOrderStatus
        let depositAmount: String?
        let filledInAmount: String?
        let filledOutAmount: String?
        let observedSourceAsset: String?
        let observedTargetAsset: String?
        let timeToExpiryBlocks: Int?
    }

    private(set) var observations: [Observation] = []
    var shouldThrow = false
    /// A specific error to throw, when the test cares which one.
    var error: Error?
    /// Status to report as STORED, when the test wants to model the store
    /// reconciling an observation into something else (e.g. a still-resting
    /// order with a confirmed cancel becoming `.cancelling`). `nil` echoes the
    /// observation back, which is what the real store does with nothing to
    /// reconcile.
    var effectiveStatus: LimitOrderStatus?

    struct WriteError: Error {}

    func recordObservation(
        inboundTxHash: String,
        pubKeyECDSA _: String,
        status: LimitOrderStatus,
        depositAmount: String?,
        filledInAmount: String?,
        filledOutAmount: String?,
        observedTradeTarget _: String?,
        observedSourceAsset: String?,
        observedTargetAsset: String?,
        timeToExpiryBlocks: Int?
    ) throws -> LimitOrderStatus {
        if let error { throw error }
        if shouldThrow { throw WriteError() }
        observations.append(Observation(
            inboundTxHash: inboundTxHash,
            status: status,
            depositAmount: depositAmount,
            filledInAmount: filledInAmount,
            filledOutAmount: filledOutAmount,
            observedSourceAsset: observedSourceAsset,
            observedTargetAsset: observedTargetAsset,
            timeToExpiryBlocks: timeToExpiryBlocks
        ))
        return effectiveStatus ?? status
    }
}

@MainActor
private final class RecordingCancelIntentStore: LimitOrderCancelIntentStoring {
    private(set) var pending: String?
    private(set) var clearedHashes: [String] = []
    var clearShouldThrow = false

    struct ClearError: Error {}

    init(pending: String?) {
        self.pending = pending
    }

    func pendingCancelBroadcast(inboundTxHash _: String, pubKeyECDSA _: String) -> String? { pending }

    func recordCancelBroadcast(inboundTxHash _: String, pubKeyECDSA _: String, txHash: String) throws {
        pending = txHash
    }

    func clearCancelBroadcast(inboundTxHash: String, pubKeyECDSA _: String, expecting txHash: String) throws {
        if clearShouldThrow { throw ClearError() }
        // Mirrors the production compare-and-set.
        guard pending == txHash else { return }
        clearedHashes.append(inboundTxHash)
        pending = nil
    }
}

@MainActor
private final class StubCancelVerifier: LimitOrderCancelVerifying {
    var outcome: LimitOrderCancelTxOutcome
    /// Runs INSIDE the lookup, so a test can model state changing while the
    /// verdict is in flight.
    var onVerify: (() -> Void)?
    private(set) var verifyCount = 0

    init(outcome: LimitOrderCancelTxOutcome) {
        self.outcome = outcome
    }

    func verifyCancelTransaction(txHash _: String, chain _: Chain) async -> LimitOrderCancelTxOutcome { // swiftlint:disable:this async_without_await
        verifyCount += 1
        onVerify?()
        return outcome
    }
}

@MainActor
private final class StubOutcomeResolver: LimitOrderOutcomeResolving {
    var outcome: LimitOrderOutcome
    private(set) var resolveCount = 0

    init(outcome: LimitOrderOutcome) {
        self.outcome = outcome
    }

    func resolveOutcome(inboundTxHash _: String, sourceChain _: Chain) async -> LimitOrderOutcome { // swiftlint:disable:this async_without_await
        resolveCount += 1
        return outcome
    }
}

@MainActor
private final class RecordingTrackingStorage: SwapTrackingStorage {
    private(set) var observedUiStatuses: [SwapTrackingUiStatus] = []
    /// The status strings mirrored onto the row, so a test can assert the row
    /// and the authoritative order table say the same thing.
    private(set) var mirroredTrackingStatuses: [String?] = []
    var inFlight: [TransactionHistoryData] = []
    var shouldThrowOnUpdate = false

    struct UpdateError: Error {}

    func updateSwapTrackingStatus(
        txHash _: String,
        pubKeyECDSA _: String,
        latestStatus _: String?,
        latestTrackingStatus: String?,
        uiStatus: SwapTrackingUiStatus,
        polledAt _: Date
    ) throws {
        if shouldThrowOnUpdate { throw UpdateError() }
        observedUiStatuses.append(uiStatus)
        mirroredTrackingStatuses.append(latestTrackingStatus)
    }

    func touchSwapTrackingLastPolled(txHash _: String, pubKeyECDSA _: String, polledAt _: Date) throws {}

    func fetchInFlightSwapTracking(providerKind _: String) throws -> [TransactionHistoryData] { inFlight }
}
