//
//  THORChainLimitTrackingService.swift
//  VultisigApp
//
//  Tracking provider for THORChain limit (`=<`) orders. Discriminated by the
//  `"thorchainLimit"` `providerKind` stored on `SwapTrackingMetadata`.
//
//  Why it exists: a placed limit order is recorded as an ordinary swap row. The
//  arbitration gate only skips native source-chain polling when a tracking
//  service resolves for the row — with none, the native `ChainPoller` confirms
//  the inbound DEPOSIT and flips the row to Successful within minutes, while the
//  order may rest unfilled for 12-72h. Registering this provider is what makes
//  the gate stand native polling down; this service then supplies the truth.
//
//  Three things make it deliberately unlike `SwapKitTrackingService`:
//
//  1. **It polls a LIST, not a hash.** `queue/limit_swaps?sender=` returns every
//     resting order for an address in one request, so the loop runs per SENDER
//     and one request serves all of that address's orders.
//  2. **Absence is the signal.** An order going terminal is never reported; it
//     simply stops being listed. The queue never says WHY, so the outcome is
//     resolved separately and never guessed.
//  3. **It never yields to native polling.** SwapKit promotes a long outage to
//     `unknownPendingExtended`, handing authority back so a source-chain
//     confirmation is at least *some* signal. For a limit order that fallback is
//     precisely the bug: confirming the deposit reports "Successful" for an
//     order that has not filled. Being slow is survivable; being wrong is not.
//     So there is no outage promotion here — it keeps retrying.
//
//  `LimitOrder` is authoritative for orders; the tx-history row mirrors it.
//

import Foundation
import OSLog

@MainActor
final class THORChainLimitTrackingService: ObservableObject, SwapTrackingService {
    // Read from non-isolated contexts (the registry dispatches on it without an
    // instance), so it can't inherit the class's MainActor isolation. A
    // compile-time constant — no shared state to protect.
    nonisolated static let providerKind: String = "thorchainLimit"

    static let shared = THORChainLimitTrackingService(
        httpClient: HTTPClient(),
        storage: TransactionHistoryStorage.shared,
        orders: LimitOrderObserver(),
        outcomes: MidgardLimitOutcomeResolver(),
        cancelIntents: LimitOrderCancelIntentStore(),
        cancelVerifier: LimitOrderCancelVerifier()
    )

    /// Latest UI status per `txHash`, observable by views that want to react
    /// without re-reading SwiftData.
    @Published private(set) var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]

    /// Polling cadence. Far slower than SwapKit's 10s: an order rests for hours
    /// or days waiting on a price, so a tighter loop would burn battery and rate
    /// limit for a state that moves on the scale of blocks.
    private static let baseInterval: TimeInterval = 60
    /// Backoff applied after the first transient failure.
    private static let backoffInitial: TimeInterval = 30
    /// Never sleep longer than this between polls.
    private static let backoffCap: TimeInterval = 5 * 60
    /// How many CONSECUTIVE polls must report an order missing before its
    /// absence is read as a closure.
    ///
    /// ⚠️ Absence is this tracker's only terminal signal, and it is not always
    /// true. The queue is reached through a load-balancing gateway whose backends
    /// are not always in sync: one has been observed answering
    /// `queue/limit_swaps?sender=…` with `total: 0`, and then `total: 1` a minute
    /// later, for an order that never left the queue and still had ~13,889 blocks
    /// of TTL. That response is well-formed and PRESENT — the `limit_swaps` key
    /// exists and the array is genuinely empty — so nothing at the decoding layer
    /// can tell it from a real closure. (The same lag surfaces elsewhere as
    /// `refusing quote on node with stale state`.)
    ///
    /// The valuable half is self-correcting: an order that reappears resets its
    /// streak, and reappearing is exactly the stale-backend signature.
    ///
    /// **Two, not three.** Three does not defeat what this actually guards
    /// against — a backend that is persistently behind, which connection reuse
    /// can pin consecutive requests to — so the extra poll buys little; only
    /// corroboration from a different source would, and that is a larger change.
    /// Against it, every additional required poll delays a genuine closure by a
    /// full cycle, and this feature's cancel attribution is time-sensitive:
    /// `LimitOrderStorageService.reconcile` credits a cancel only while the TTL
    /// demonstrably has not elapsed, so waiting longer actively degrades it. Two
    /// costs a minute and closes the single-blip window — the one that has
    /// actually been observed.
    private static let absencePollsBeforeClosing = 2

    private let httpClient: HTTPClientProtocol
    private let storage: SwapTrackingStorage
    private let orders: LimitOrderObserving
    private let outcomes: LimitOrderOutcomeResolving
    private let cancelIntents: LimitOrderCancelIntentStoring
    private let cancelVerifier: LimitOrderCancelVerifying
    private let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-limit-tracking")

    /// Rows this service owns, keyed by `txHash`.
    private var tracked: [String: TrackedOrder] = [:]
    /// One polling task per SENDER address — the unit the queue endpoint is
    /// scoped to. A vault with orders from several source chains runs one task
    /// per source address in play, still far fewer than one per order.
    private var senderTasks: [String: Task<Void, Never>] = [:]
    /// Identifies the CURRENT poll task per sender. A cancelled task can still
    /// be suspended in an await; without a generation token it would wake up
    /// later and tear down the bookkeeping of the task that replaced it —
    /// orphaning a live loop that nothing can then cancel, and letting the next
    /// start spawn a duplicate.
    private var senderTokens: [String: UUID] = [:]
    /// Current backoff per sender, present only while a failure streak is
    /// running. Absent means "no failures" — which is what makes the first
    /// failure wait `backoffInitial` rather than double the healthy cadence.
    private var senderBackoff: [String: TimeInterval] = [:]
    private var isActive: Bool = true
    /// Cancel transactions this device has already settled a verdict on, so a
    /// still-resting order is not re-checked on every one-minute poll for the
    /// whole time it takes THORChain to actually drop it from the queue.
    ///
    /// A failed cancel is never in here: its record is withdrawn on the spot, so
    /// there is nothing left to re-check.
    private var settledCancelHashes: Set<String> = []
    /// Consecutive polls that have found each order missing from the queue,
    /// keyed by `txHash`. Absent means "seen resting on the last poll".
    ///
    /// Only advanced by a poll that actually answered: a network failure or an
    /// unrecognised envelope returns before reconciliation, so neither counts as
    /// evidence of absence.
    private var absentPollStreaks: [String: Int] = [:]

    init(
        httpClient: HTTPClientProtocol,
        storage: SwapTrackingStorage,
        orders: LimitOrderObserving,
        outcomes: LimitOrderOutcomeResolving,
        cancelIntents: LimitOrderCancelIntentStoring,
        cancelVerifier: LimitOrderCancelVerifying
    ) {
        self.httpClient = httpClient
        self.storage = storage
        self.orders = orders
        self.outcomes = outcomes
        self.cancelIntents = cancelIntents
        self.cancelVerifier = cancelVerifier
    }

    // MARK: - SwapTrackingService

    func start(tx: TransactionHistoryData) {
        guard isOwnedByThisProvider(tx) else {
            logger.debug("Skipping non-limit row \(tx.txHash, privacy: .public)")
            return
        }
        // Seed from whatever was last persisted so a view mounting before the
        // first poll (e.g. after relaunch on a still-resting order) shows the
        // right state rather than a default.
        uiStatusByTxHash[tx.txHash] = tx.swapTrackingUiStatus
        guard !tx.swapTrackingUiStatus.isTerminal else {
            logger.debug("Skipping terminal limit row \(tx.txHash, privacy: .public)")
            return
        }
        // The queue is addressed by the SOURCE-CHAIN sender. With no sender
        // there is nothing to poll — leave the row alone rather than fetch the
        // entire network's queue.
        guard !tx.fromAddress.isEmpty else {
            logger.error("Limit row \(tx.txHash, privacy: .public) has no sender address — cannot track")
            return
        }
        guard tracked[tx.txHash] == nil else { return }

        tracked[tx.txHash] = TrackedOrder(
            txHash: tx.txHash,
            pubKeyECDSA: tx.pubKeyECDSA,
            sender: tx.fromAddress,
            sourceChain: Chain(rawValue: tx.chainRawValue)
        )
        startPolling(sender: tx.fromAddress)
    }

    func stop(txHash: String) {
        guard let order = tracked.removeValue(forKey: txHash) else { return }
        absentPollStreaks.removeValue(forKey: txHash)
        stopPollingIfSenderIdle(order.sender)
    }

    /// Re-scan SwiftData for non-terminal limit rows and take them up.
    /// Idempotent — already-tracked rows are left alone.
    func resumeInFlight() async { // swiftlint:disable:this async_without_await
        let inFlight: [TransactionHistoryData]
        do {
            inFlight = try storage.fetchInFlightSwapTracking(providerKind: Self.providerKind)
        } catch {
            logger.error("Failed to fetch in-flight limit orders: \(error.localizedDescription, privacy: .public)")
            return
        }
        for tx in inFlight {
            start(tx: tx)
        }
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if active {
            for sender in Set(tracked.values.map(\.sender)) {
                startPolling(sender: sender)
            }
        } else {
            // Keep `tracked` — it's what `setActive(true)` resumes from.
            for sender in Array(senderTasks.keys) {
                cancelPolling(sender: sender)
            }
        }
    }

    /// Cancel every sender poll task and drop ALL in-memory tracking state —
    /// `tracked`, the per-sender tasks/tokens/backoff, the absence streaks, the
    /// settled-cancel set, and the observable UI cache. A hard teardown for the
    /// global reset, distinct from `setActive(false)`, which keeps `tracked` so
    /// foreground can resume. Nothing is left to resume from here: the rows
    /// these tasks poll are being deleted, and a `resumeInFlight` after a reset
    /// re-reads an empty table and starts nothing.
    func stopAllTracking() {
        for sender in Array(senderTasks.keys) {
            cancelPolling(sender: sender)
        }
        tracked.removeAll()
        absentPollStreaks.removeAll()
        settledCancelHashes.removeAll()
        uiStatusByTxHash.removeAll()
        logger.info("Stopped all limit-order tracking (reset)")
    }

    // MARK: - Test-only inspection

    var trackedOrderCountForTesting: Int { tracked.count }
    var isActiveForTesting: Bool { isActive }
    var activeSenderPollCountForTesting: Int { senderTasks.count }
    /// So tests drive exactly the number of polls the rule requires rather than
    /// hardcoding a number that would quietly stop matching it.
    static var absencePollsBeforeClosingForTesting: Int { absencePollsBeforeClosing }

    /// Drives exactly one poll cycle for `sender`, bypassing the schedule, so
    /// tests can exercise the state machine without sleeping.
    func pollOnceForTesting(sender: String) async {
        _ = await pollOnce(sender: sender)
    }

    // MARK: - Polling lifecycle

    private func startPolling(sender: String) {
        guard isActive, senderTasks[sender] == nil else { return }
        let token = UUID()
        senderTokens[sender] = token
        senderBackoff.removeValue(forKey: sender)
        senderTasks[sender] = Task { [weak self] in
            // `self` is re-acquired per iteration and deliberately NOT held
            // across the sleep: a loop that waits a minute between polls would
            // otherwise keep the service alive for that minute after everything
            // else let go of it. Once it's gone, the next iteration ends.
            while !Task.isCancelled {
                guard let outcome = await self?.pollOnce(sender: sender, token: token) else { return }
                // Cancellation can land while the poll is in flight; check
                // before acting on a result nobody is waiting for any more.
                if Task.isCancelled { return }
                if outcome.shouldStop {
                    self?.finishPolling(sender: sender, token: token)
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(outcome.nextDelay))
                } catch {
                    return
                }
            }
        }
    }

    /// Tears down bookkeeping only if this task is still the current one for the
    /// sender. A superseded task waking from an await must not evict its
    /// replacement.
    private func finishPolling(sender: String, token: UUID) {
        guard senderTokens[sender] == token else { return }
        senderTasks.removeValue(forKey: sender)
        senderTokens.removeValue(forKey: sender)
        senderBackoff.removeValue(forKey: sender)
    }

    private func stopPollingIfSenderIdle(_ sender: String) {
        guard !tracked.values.contains(where: { $0.sender == sender }) else { return }
        cancelPolling(sender: sender)
    }

    private func cancelPolling(sender: String) {
        senderTasks.removeValue(forKey: sender)?.cancel()
        senderTokens.removeValue(forKey: sender)
        senderBackoff.removeValue(forKey: sender)
    }

    // MARK: - One poll cycle

    /// - Parameter token: the generation this poll belongs to, or `nil` when
    ///   driven directly (tests). Every await is a chance for this task to be
    ///   superseded — by a background/foreground cycle, say — so the generation
    ///   is re-checked before ANY mutation. A stale task that skipped the check
    ///   could write, release, or reschedule against the live generation's
    ///   state, using an answer fetched for a loop that no longer exists.
    private func pollOnce(sender: String, token: UUID? = nil) async -> PollOutcome {
        guard tracked.values.contains(where: { $0.sender == sender }) else {
            return PollOutcome(shouldStop: true, nextDelay: 0)
        }
        do {
            let response = try await httpClient.request(
                ThorchainMainnetAPI(.limitSwapQueue(sender: sender)),
                responseType: ThorchainLimitSwapQueueResponse.self
            )
            guard isCurrentGeneration(sender: sender, token: token) else {
                return PollOutcome(shouldStop: true, nextDelay: 0)
            }
            guard let resting = response.data.limitSwaps else {
                // The `limit_swaps` key was absent: a response we don't
                // understand, NOT an empty queue. Reading it as empty would
                // close every one of this sender's orders at once. Back off and
                // ask again.
                logger.error("Limit queue response carried no limit_swaps key — treating as unknown, not empty")
                return backoff(sender: sender)
            }
            return await reconcile(sender: sender, resting: resting, token: token)
        } catch {
            logger.debug("Limit queue poll failed: \(error.localizedDescription, privacy: .public)")
            guard isCurrentGeneration(sender: sender, token: token) else {
                return PollOutcome(shouldStop: true, nextDelay: 0)
            }
            return backoff(sender: sender)
        }
    }

    /// Whether this task is still the sender's live poll loop. `nil` means the
    /// caller isn't generation-scoped (a directly-driven poll), so it's current
    /// by definition.
    private func isCurrentGeneration(sender: String, token: UUID?) -> Bool {
        guard let token else { return true }
        return senderTokens[sender] == token
    }

    /// Compare what the queue reports against what we're tracking.
    ///
    /// Presence means resting. ABSENCE means the order closed — the only terminal
    /// signal the queue gives, and one a desynced backend can fabricate, so it
    /// has to be seen on `absencePollsBeforeClosing` consecutive polls before it
    /// is acted on. Until then the order keeps whatever state it already has:
    /// nothing is written, so the last good resting observation — its fill split
    /// and its expiry countdown — is left exactly as it was, and no third
    /// "possibly gone" state is invented.
    private func reconcile(
        sender: String,
        resting: [ThorchainLimitSwapQueueEntry],
        token: UUID?
    ) async -> PollOutcome {
        // Hex case is not semantic, and the queue's casing needn't match the
        // hash we broadcast under, so match case-insensitively.
        let restingByHash = Dictionary(
            resting.map { ($0.swap.tx.id.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for order in tracked.values where order.sender == sender {
            if let entry = restingByHash[order.txHash.uppercased()] {
                // Back in the queue, so any absence recorded earlier was wrong.
                // This reset is the self-correcting half of the guard, and a
                // reappearance is the stale-backend signature itself.
                if let streak = absentPollStreaks.removeValue(forKey: order.txHash) {
                    logger.info("Limit order \(order.txHash, privacy: .public) is back in the queue after \(streak, privacy: .public) absent poll(s) — that absence was not a closure")
                }
                // Re-check the cancel record BEFORE recording the observation,
                // not after. `observeResting` reconciles against that record — a
                // present hash is what makes a resting order read `.cancelling` —
                // so verifying second would persist and mirror `.cancelling` on
                // the strength of a hash this very cycle then withdraws, leaving
                // the row saying "Cancelling…" for an order whose authoritative
                // record is back to `.pending` until the next poll repairs it.
                guard await verifyPendingCancel(order: order, sender: sender, token: token) else {
                    return PollOutcome(shouldStop: true, nextDelay: 0)
                }
                observeResting(order: order, entry: entry)
            } else {
                // Clamped once corroborated. An order can stay absent for many
                // polls without being released — an outcome Midgard has not
                // indexed yet, or a write that failed — and the streak is only
                // ever compared against the threshold, so counting past it
                // measures nothing and grows without bound.
                let streak = min((absentPollStreaks[order.txHash] ?? 0) + 1, Self.absencePollsBeforeClosing)
                absentPollStreaks[order.txHash] = streak
                guard streak >= Self.absencePollsBeforeClosing else {
                    // Uncorroborated. Nothing is written and nothing is
                    // released — the order keeps the state and the last resting
                    // observation it already had, and we ask again.
                    logger.info("Limit order \(order.txHash, privacy: .public) missing from the queue on absent poll \(streak, privacy: .public) of \(Self.absencePollsBeforeClosing, privacy: .public) — not treating it as closed yet")
                    continue
                }
                guard await observeClosed(order: order, sender: sender, token: token) else {
                    // Superseded mid-reconcile — the live generation owns these
                    // orders now, and will re-poll them itself.
                    return PollOutcome(shouldStop: true, nextDelay: 0)
                }
            }
        }

        // A successful poll ends any failure streak, so the next failure starts
        // over at `backoffInitial` rather than resuming a stale escalation.
        senderBackoff.removeValue(forKey: sender)
        return PollOutcome(
            shouldStop: !tracked.values.contains(where: { $0.sender == sender }),
            nextDelay: Self.baseInterval
        )
    }

    /// Still queued: record the fill split and the expiry countdown, and keep it
    /// resting.
    private func observeResting(order: TrackedOrder, entry: ThorchainLimitSwapQueueEntry) {
        // `.pending` is the OBSERVATION — the order is in the queue. The store
        // may reconcile it to `.cancelling` if this device has a confirmed
        // cancel against it; either way the order stays non-terminal and tracked.
        write(order: order, status: .pending, entry: entry)
    }

    /// Re-check the cancel transaction recorded against a STILL-RESTING order,
    /// and withdraw the record if that transaction failed.
    ///
    /// ⚠️ The self-heal for the failure a broadcast hash cannot describe. A
    /// cancel can be included in a block and still be REFUSED by the handler —
    /// THORChain answers `could not find matching limit swap` with a non-zero
    /// code — and a record kept on that basis disables the Cancel button for
    /// good on an order that is still resting, and pre-labels its eventual
    /// closure "Cancelled". The done screen verifies before recording, but it
    /// only runs while it is on screen: an app killed mid-verification, or an
    /// order whose record predates that check, is repaired here instead.
    ///
    /// Only for RESTING orders, and that is not an optimisation. Once an order
    /// leaves the queue the record has already done its work — `reconcile` read
    /// it to tell a cancellation from a plain refund — and withdrawing it then
    /// would rewrite settled history from a lookup that may simply have been
    /// rate-limited.
    ///
    /// - Returns: `false` if this task was superseded while the lookup was in
    ///   flight, meaning the caller must stop rather than act on it.
    private func verifyPendingCancel(order: TrackedOrder, sender: String, token: UUID?) async -> Bool {
        guard let sourceChain = order.sourceChain,
              let cancelHash = cancelIntents.pendingCancelBroadcast(
                  inboundTxHash: order.txHash,
                  pubKeyECDSA: order.pubKeyECDSA
              ),
              !settledCancelHashes.contains(cancelHash) else {
            return true
        }
        let outcome = await cancelVerifier.verifyCancelTransaction(txHash: cancelHash, chain: sourceChain)
        guard isCurrentGeneration(sender: sender, token: token) else { return false }
        switch outcome {
        case .succeeded, .delivered:
            // Persist the confirmation FIRST, so `reconcile`'s no-reason refund
            // fallback may credit this cancel a later closure. Entry into
            // `.cancelling` happened on broadcast; this terminal promotion waits
            // for exactly this verdict.
            do {
                try cancelIntents.confirmCancelBroadcast(
                    inboundTxHash: order.txHash,
                    pubKeyECDSA: order.pubKeyECDSA,
                    txHash: cancelHash
                )
                // Only NOW mark it settled. `.delivered` will not become anything
                // else on a re-ask either — THORChain's verdict on an L1 cancel is
                // not observable — so re-checking an immutable receipt every
                // minute buys nothing. But if the confirmation write above threw,
                // the hash is deliberately left un-settled so the next poll
                // retries the persistence rather than skipping it forever.
                settledCancelHashes.insert(cancelHash)
            } catch {
                logger.error("Failed to record cancel confirmation: \(error.localizedDescription, privacy: .public)")
            }
        case .unresolved:
            // Not an answer. Ask again next poll rather than withdraw a record
            // on a rate limit.
            break
        case let .failed(reason):
            logger.error("Cancel \(cancelHash, privacy: .public) failed on-chain — withdrawing the record: \(reason, privacy: .public)")
            do {
                // Compare-and-set on the hash we actually verified: the lookup
                // above is a network round-trip, and a cancel recorded in the
                // meantime is a different transaction that this verdict says
                // nothing about.
                try cancelIntents.clearCancelBroadcast(
                    inboundTxHash: order.txHash,
                    pubKeyECDSA: order.pubKeyECDSA,
                    expecting: cancelHash
                )
            } catch {
                logger.error("Failed to withdraw the cancel record: \(error.localizedDescription, privacy: .public)")
            }
        }
        return true
    }

    /// Gone from the queue, so it closed — but the queue never says why.
    /// Resolve the outcome; if it isn't knowable yet, leave the order resting
    /// and ask again. A guess here is permanent: nothing revisits a terminal
    /// order.
    ///
    /// - Returns: `false` if this task was superseded while the outcome lookup
    ///   was in flight, meaning the caller must stop rather than act on it.
    private func observeClosed(order: TrackedOrder, sender: String, token: UUID?) async -> Bool {
        guard let sourceChain = order.sourceChain else {
            logger.error("Limit order \(order.txHash, privacy: .public) has no source chain — cannot resolve outcome")
            return true
        }
        let outcome = await outcomes.resolveOutcome(inboundTxHash: order.txHash, sourceChain: sourceChain)
        // The lookup is a network round-trip: re-check before writing or
        // releasing anything on the strength of it.
        guard isCurrentGeneration(sender: sender, token: token) else { return false }
        switch outcome {
        case .unresolved:
            // Almost always Midgard indexing lag. Stay resting; ask next poll.
            logger.debug("Limit order \(order.txHash, privacy: .public) left the queue; outcome not resolvable yet")
        case .filled:
            if write(order: order, status: .filled, entry: nil) {
                release(order)
            }
        case .cancelled, .expired:
            // THORChain's own account of why it closed the order, read off the
            // refund action Midgard indexes. Nothing local is consulted: this is
            // as true for an order cancelled from another device, or another
            // wallet, as for one this app cancelled itself.
            if write(order: order, status: outcome == .cancelled ? .cancelled : .expired, entry: nil) {
                release(order)
            }
        case .refunded:
            // The funds came back and the chain gave no reason we recognise.
            // Recorded as the observable fact, and the store may still promote
            // it to `.cancelled` on the older evidence — a cancel this device
            // confirmed, against an order whose TTL demonstrably had not
            // elapsed. That path is now the fallback, not the rule.
            if write(order: order, status: .refunded, entry: nil) {
                release(order)
            }
        }
        return true
    }

    /// Write to `LimitOrder` (authoritative), then mirror onto the row.
    ///
    /// `entry == nil` leaves the stored split and expiry countdown untouched: a
    /// terminal order is already gone from the queue, so the last resting
    /// observation is the final word on how much of it filled — and a countdown
    /// for a closed order is meaningless.
    ///
    /// The row mirrors the status the order table actually STORED, which is not
    /// always the one observed: a still-resting order with a confirmed cancel
    /// against it is reconciled to `.cancelling`. Mirroring the raw observation
    /// would leave the row calling that order "pending" — and the row's UI
    /// status is what the surfaces read after a relaunch.
    ///
    /// - Returns: whether the AUTHORITATIVE write landed. The caller must not
    ///   release an order on `false`: dropping it after a failed write would
    ///   leave `LimitOrder` permanently non-terminal with nothing left to
    ///   correct it, while the row had already moved on — the two tables
    ///   disagreeing forever, which is the exact failure this branch exists to
    ///   end. Staying tracked just means asking again.
    @discardableResult
    private func write(
        order: TrackedOrder,
        status: LimitOrderStatus,
        entry: ThorchainLimitSwapQueueEntry?
    ) -> Bool {
        let state = entry?.swap.state
        // Whether this device holds the authoritative `LimitOrder` record. On a
        // co-signer it does not, which changes what a failed row mirror means
        // below: with no local order behind it, the row is not a mirror of the
        // truth, it IS the truth.
        var hasLocalOrder = true
        // Defaults to the observation, which is the right answer on a co-signer:
        // with no local order there is nothing to reconcile against.
        var effectiveStatus = status
        do {
            effectiveStatus = try orders.recordObservation(
                inboundTxHash: order.txHash,
                pubKeyECDSA: order.pubKeyECDSA,
                status: status,
                depositAmount: state?.deposit,
                filledInAmount: state?.inAmount,
                filledOutAmount: state?.outAmount,
                observedTradeTarget: entry?.swap.tradeTarget,
                // The assets THORChain resolved this order to. Empty strings are
                // dropped rather than stored: a blank asset is not an
                // observation, and persisting one would overwrite a good value
                // with something no memo can be built from.
                observedSourceAsset: entry?.swap.tx.coins?.first?.asset?.memoForm.trimmedNonEmpty,
                observedTargetAsset: entry?.swap.targetAsset?.memoForm.trimmedNonEmpty,
                // Every numeric field on this endpoint arrives as a string. An
                // unparseable countdown is dropped rather than defaulted: `0`
                // would render "expired" on an order that is resting fine.
                //
                // `Int($0)`, never `flatMap(Int.init)`: an unapplied `Int.init`
                // resolves to this codebase's `Int.init?(hex:)` extension —
                // argument labels are erased when an initializer is converted
                // to a function value, and that overload matches
                // `(String) -> Int?` too. The countdown would then be read as
                // base-16 and silently report ~6x the real time remaining.
                timeToExpiryBlocks: entry?.timeToExpiryBlocks.flatMap { Int($0) }
            )
        } catch LimitOrderStorageError.notFound {
            // Expected on a CO-SIGNER: `LimitOrder` is written by the device
            // that placed the order, so a co-signing device tracks a row it has
            // no local order record for. That's not a failed write — there is
            // nothing here to write to, and the row IS the whole picture on this
            // device. Retrying forever would peg the row at "resting" for good.
            hasLocalOrder = false
            logger.debug("No local limit order for \(order.txHash, privacy: .public) — mirroring onto the row only")
        } catch {
            logger.error("Failed to record limit-order observation: \(error.localizedDescription, privacy: .public)")
            return false
        }

        // Derived from the stored status rather than passed in: the mapper is
        // the single definition of what a `LimitOrderStatus` looks like on a
        // row, and a separately-supplied UI status is a second copy of that
        // table waiting to disagree with it.
        let uiStatus = THORChainLimitTrackingStatusMapper.map(effectiveStatus)
        do {
            try storage.updateSwapTrackingStatus(
                txHash: order.txHash,
                pubKeyECDSA: order.pubKeyECDSA,
                latestStatus: effectiveStatus.rawValue,
                // The row's tracking vocabulary IS `LimitOrderStatus` — see
                // `THORChainLimitTrackingStatusMapper`.
                latestTrackingStatus: effectiveStatus.rawValue,
                uiStatus: uiStatus,
                polledAt: Date()
            )
        } catch {
            // Normally the row is a mirror of `LimitOrder`, which now holds the
            // truth. A failed mirror is worth knowing about but doesn't
            // invalidate the authoritative write, so it doesn't hold the order
            // open.
            logger.error("Failed to mirror limit status onto the row: \(error.localizedDescription, privacy: .public)")
            // On a CO-SIGNER there is no local order behind the row, so this
            // write was not a mirror of anything — it was the only persisted
            // terminal state this device will ever have. Reporting success
            // would release the order and strand the row as non-terminal for
            // the rest of the session, with nothing left to correct it. Stay
            // tracked and ask again.
            if !hasLocalOrder {
                return false
            }
        }

        uiStatusByTxHash[order.txHash] = uiStatus
        return true
    }

    private func release(_ order: TrackedOrder) {
        tracked.removeValue(forKey: order.txHash)
        absentPollStreaks.removeValue(forKey: order.txHash)
    }

    /// Back off after a failed poll: `backoffInitial`, then doubling to
    /// `backoffCap`.
    ///
    /// The streak's absence — not the healthy cadence — is the starting point.
    /// Doubling `baseInterval` instead would make the FIRST failure wait twice
    /// the normal poll, so the declared initial backoff would never be used.
    ///
    /// Never promotes to an outage: handing authority back to native polling
    /// would let a deposit confirmation report a resting order as Successful.
    private func backoff(sender: String) -> PollOutcome {
        let next: TimeInterval
        if let current = senderBackoff[sender] {
            next = min(current * 2, Self.backoffCap)
        } else {
            next = Self.backoffInitial
        }
        senderBackoff[sender] = next
        return PollOutcome(shouldStop: false, nextDelay: next)
    }

    private func isOwnedByThisProvider(_ tx: TransactionHistoryData) -> Bool {
        tx.swapTracking?.providerKind == Self.providerKind
    }
}

extension THORChainLimitTrackingService {
    /// The tracking metadata a limit-order row must carry for the arbitration
    /// gate to hand this provider authority over it.
    ///
    /// One factory shared by the initiator and co-signer recording paths — the
    /// gate turns on `providerKind` alone, so a path that built the metadata
    /// slightly differently would still be gated, but would then be tracked
    /// with the wrong identifiers. A limit order is identified on-chain by its
    /// inbound tx hash; there is no aggregator-issued swap/route id to carry.
    nonisolated static func metadata(
        broadcastHash: String,
        sourceChain: Chain
    ) -> SwapTrackingMetadataData {
        SwapTrackingMetadataData(
            providerKind: providerKind,
            swapId: nil,
            routeId: nil,
            broadcastHash: broadcastHash,
            sourceChainId: sourceChain.rawValue,
            subProvider: nil
        )
    }
}

// MARK: - Internal types

private struct TrackedOrder {
    let txHash: String
    let pubKeyECDSA: String
    /// Source-chain address the queue is scoped by.
    let sender: String
    /// Source chain of the inbound deposit — where the outcome is looked up.
    let sourceChain: Chain?
}

private struct PollOutcome {
    let shouldStop: Bool
    let nextDelay: TimeInterval
}
