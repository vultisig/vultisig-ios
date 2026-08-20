//
//  TransactionStatusPoller.swift
//  VultisigApp
//

import Combine
import Foundation
import OSLog

@MainActor
final class TransactionStatusPoller: ObservableObject {
    static let shared = TransactionStatusPoller()

    enum PollAction: Equatable {
        case complete(TransactionHistoryStatus, String?)
        case retry
        case stop
    }

    @Published private(set) var completedTransactionCount: Int = 0

    private let service = TransactionStatusService.shared
    private let recorder = TransactionHistoryRecorder.shared
    private let historyStorage = TransactionHistoryStorage.shared
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var taskTokens: [String: UUID] = [:]
    private let logger = Log.chain.other

    private init() {}

    /// Typed entry point for the tx-history viewmodel. Routes through the
    /// `txHash`-keyed core implementation after enforcing the swap-tracker
    /// gate.
    ///
    /// Defensive guard: rows owned by a registered `SwapTrackingService`
    /// (looked up via `SwapTrackingRegistry`) are exclusively that service's
    /// territory unless `swapTracking.trackerOutage == true`, in which case
    /// native polling is the fallback signal source. This guard duplicates
    /// the higher-level filter in
    /// `TransactionHistoryViewModel.pollInProgressTransactions` so a future
    /// caller can't accidentally re-introduce the dual-polling regression
    /// that lets a source-chain confirmation overwrite a still-in-flight
    /// cross-chain swap as `.successful`.
    ///
    /// Kept even though the core `poll(txHash:…)` now enforces the same gate:
    /// this overload already holds the row, so it answers without a refetch
    /// and reports the decision back through its `Bool` return.
    @discardableResult
    func poll(
        tx: TransactionHistoryData,
        onUpdate: @escaping (TransactionHistoryStatus, String?) -> Void
    ) -> Bool {
        if SwapTrackingRegistry.shared.service(for: tx) != nil
            && tx.swapTracking?.trackerOutage != true {
            logger.debug("Skipping native poll for swap-tracked tx \(tx.txHash) — tracker is authoritative")
            return false
        }
        guard let chain = Chain(rawValue: tx.chainRawValue) else { return false }
        poll(
            txHash: tx.txHash,
            chain: chain,
            createdAt: tx.createdAt,
            pubKeyECDSA: tx.pubKeyECDSA,
            onUpdate: onUpdate
        )
        return true
    }

    /// Start polling a transaction. Calls `onUpdate` on the main actor when status changes.
    ///
    /// Enforces the swap-tracker gate itself rather than trusting callers to.
    /// This is the single choke point every native poll funnels through — the
    /// typed `poll(tx:)` overload included — so a caller that only has a hash
    /// (`pollPendingTransactions`) can't route around it.
    func poll(
        txHash: String,
        chain: Chain,
        createdAt: Date,
        pubKeyECDSA: String,
        onUpdate: @escaping (TransactionHistoryStatus, String?) -> Void
    ) {
        guard activeTasks[txHash] == nil else { return }
        guard !isOwnedByTracker(txHash: txHash, pubKeyECDSA: pubKeyECDSA) else {
            logger.debug("Skipping native poll for swap-tracked tx \(txHash) — tracker is authoritative")
            return
        }

        let token = UUID()
        taskTokens[txHash] = token
        let config = ChainStatusConfig.config(for: chain)

        let task = Task { [weak self] in
            pollingLoop: while !Task.isCancelled {
                guard let self else { break }

                do {
                    // Ownership is re-checked before every write, not just at
                    // start. A poll that legitimately began under
                    // `trackerOutage` must not still be holding the pen when the
                    // tracker recovers — the gate has to hold for the write, and
                    // the write is what the user sees.
                    guard !self.isOwnedByTracker(txHash: txHash, pubKeyECDSA: pubKeyECDSA) else {
                        self.logger.debug("Tracker regained authority mid-poll for \(txHash) — standing down")
                        break
                    }

                    let elapsed = Date().timeIntervalSince(createdAt)
                    let action = await Self.nextAction(
                        checker: self.service,
                        txHash: txHash,
                        chain: chain,
                        deadlineReached: elapsed >= config.maxWaitTime
                    )

                    // `stopAll()` (e.g. the global reset) cancels this task while
                    // the status request is in flight. A late result must not be
                    // written back or published for a row that is being deleted —
                    // re-check cancellation after the await, not just at the top
                    // of the loop.
                    if Task.isCancelled { break }

                    switch action {
                    case let .complete(historyStatus, errorMessage):
                        // Re-checked after the await: the status fetch is a
                        // network round-trip, and the tracker can take ownership
                        // while it is in flight.
                        guard !self.isOwnedByTracker(txHash: txHash, pubKeyECDSA: pubKeyECDSA) else {
                            self.logger.debug("Tracker took authority during status fetch for \(txHash) — discarding result")
                            break pollingLoop
                        }
                        self.recorder.updateStatus(
                            txHash: txHash,
                            pubKeyECDSA: pubKeyECDSA,
                            status: historyStatus,
                            errorMessage: errorMessage
                        )
                        onUpdate(historyStatus, errorMessage)
                        self.completedTransactionCount += 1
                        break pollingLoop

                    case .retry:
                        try await Task.sleep(for: .seconds(config.pollInterval))

                    case .stop:
                        // The client deadline limits continuous polling; it is
                        // not evidence that the chain rejected the transaction.
                        // Leave the row in progress so the next app/history open
                        // performs another chain-first check.
                        break pollingLoop
                    }
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
            }

            self?.cleanupTask(txHash: txHash, token: token)
        }
        activeTasks[txHash] = task
    }

    func stopPolling(txHash: String) {
        activeTasks[txHash]?.cancel()
        activeTasks.removeValue(forKey: txHash)
        taskTokens.removeValue(forKey: txHash)
    }

    func stopAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        taskTokens.removeAll()
    }

    private func cleanupTask(txHash: String, token: UUID) {
        guard taskTokens[txHash] == token else { return }
        activeTasks.removeValue(forKey: txHash)
        taskTokens.removeValue(forKey: txHash)
    }

    /// Start polling all pending transactions for a vault.
    func pollPendingTransactions(pubKeyECDSA: String) {
        do {
            let pending = try StoredPendingTransactionStorage.shared.getAllPending()
            for tx in pending where tx.pubKeyECDSA == pubKeyECDSA {
                poll(txHash: tx.txHash, chain: tx.chain, createdAt: tx.createdAt, pubKeyECDSA: pubKeyECDSA) { _, _ in }
            }
        } catch {
            logger.error("Failed to fetch pending transactions: \(error)")
        }
    }

    private func isOwnedByTracker(txHash: String, pubKeyECDSA: String) -> Bool {
        let tx: TransactionHistoryData?
        do {
            tx = try historyStorage.fetchTransaction(txHash: txHash, pubKeyECDSA: pubKeyECDSA)
        } catch {
            // A fetch failure is NOT the same as "no such row", so don't let it
            // collapse into one silently. Both fall open (below), but only this
            // one means the store is unreadable — in which case the status write
            // this gate is protecting would fail against that same store anyway.
            logger.error("Tracker-gate lookup failed for \(txHash, privacy: .public); treating as untracked: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return Self.isTrackerAuthoritative(for: tx, registry: .shared)
    }

    /// Whether a registered `SwapTrackingService` owns this row and is
    /// currently authoritative for it — i.e. native polling must stand down.
    ///
    /// Pure, and separated from the fetch, so the decision is testable without
    /// the poller's singletons or its network-backed polling task.
    ///
    /// - A row with no history entry (or an unreadable store) is `nil` here and
    ///   treated as UNOWNED, so ordinary sends still poll. The gate must only
    ///   ever *withhold* native polling from rows a tracker actually drives —
    ///   failing the other way would silently stop every send from confirming.
    /// - `trackerOutage == true` hands authority back: the tracker has been
    ///   unavailable long enough that a source-chain confirmation beats no
    ///   signal at all.
    static func isTrackerAuthoritative(
        for tx: TransactionHistoryData?,
        registry: SwapTrackingRegistry
    ) -> Bool {
        guard let tx else { return false }
        return registry.service(for: tx) != nil
            && tx.swapTracking?.trackerOutage != true
    }

    /// Resolve one polling iteration. The chain lookup always happens before
    /// the client deadline is interpreted, including when a row is already old
    /// when the app opens.
    static func nextAction(
        checker: TransactionStatusChecking,
        txHash: String,
        chain: Chain,
        deadlineReached: Bool
    ) async -> PollAction {
        do {
            let result = try await checker.checkTransactionStatus(txHash: txHash, chain: chain)
            switch result.status {
            case .confirmed:
                return .complete(.successful, nil)
            case let .failed(reason):
                return .complete(.error, reason)
            case .notFound, .pending:
                return deadlineReached ? .stop : .retry
            }
        } catch is CancellationError {
            return .stop
        } catch {
            return deadlineReached ? .stop : .retry
        }
    }
}
