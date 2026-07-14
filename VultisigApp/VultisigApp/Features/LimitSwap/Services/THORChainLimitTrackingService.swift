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
        outcomes: MidgardLimitOutcomeResolver()
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

    private let httpClient: HTTPClientProtocol
    private let storage: SwapTrackingStorage
    private let orders: LimitOrderObserving
    private let outcomes: LimitOrderOutcomeResolving
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

    init(
        httpClient: HTTPClientProtocol,
        storage: SwapTrackingStorage,
        orders: LimitOrderObserving,
        outcomes: LimitOrderOutcomeResolving
    ) {
        self.httpClient = httpClient
        self.storage = storage
        self.orders = orders
        self.outcomes = outcomes
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

    // MARK: - Test-only inspection

    var trackedOrderCountForTesting: Int { tracked.count }
    var isActiveForTesting: Bool { isActive }
    var activeSenderPollCountForTesting: Int { senderTasks.count }

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
    /// Presence means resting. ABSENCE means the order closed — the only
    /// terminal signal the queue gives.
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
                observeResting(order: order, entry: entry)
            } else {
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

    /// Still queued: record the fill split and keep it resting.
    private func observeResting(order: TrackedOrder, entry: ThorchainLimitSwapQueueEntry) {
        write(order: order, status: .pending, uiStatus: .resting, state: entry.swap.state)
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
            if write(order: order, status: .filled, uiStatus: .completed, state: nil) {
                release(order)
            }
        case .expired:
            if write(order: order, status: .expired, uiStatus: .expired, state: nil) {
                release(order)
            }
        }
        return true
    }

    /// Write to `LimitOrder` (authoritative), then mirror onto the row.
    ///
    /// `state == nil` leaves the stored split untouched: a terminal order is
    /// already gone from the queue, so the last resting observation is the final
    /// word on how much of it filled.
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
        uiStatus: SwapTrackingUiStatus,
        state: ThorchainQueuedSwapState?
    ) -> Bool {
        do {
            try orders.recordObservation(
                inboundTxHash: order.txHash,
                pubKeyECDSA: order.pubKeyECDSA,
                status: status,
                depositAmount: state?.deposit,
                filledInAmount: state?.inAmount,
                filledOutAmount: state?.outAmount
            )
        } catch {
            logger.error("Failed to record limit-order observation: \(error.localizedDescription, privacy: .public)")
            return false
        }

        do {
            try storage.updateSwapTrackingStatus(
                txHash: order.txHash,
                pubKeyECDSA: order.pubKeyECDSA,
                latestStatus: status.rawValue,
                // The row's tracking vocabulary IS `LimitOrderStatus` — see
                // `THORChainLimitTrackingStatusMapper`.
                latestTrackingStatus: status.rawValue,
                uiStatus: uiStatus,
                polledAt: Date()
            )
        } catch {
            // The row is a mirror of `LimitOrder`, which now holds the truth.
            // A failed mirror is worth knowing about but doesn't invalidate the
            // authoritative write, so it doesn't hold the order open.
            logger.error("Failed to mirror limit status onto the row: \(error.localizedDescription, privacy: .public)")
        }

        uiStatusByTxHash[order.txHash] = uiStatus
        return true
    }

    private func release(_ order: TrackedOrder) {
        tracked.removeValue(forKey: order.txHash)
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
