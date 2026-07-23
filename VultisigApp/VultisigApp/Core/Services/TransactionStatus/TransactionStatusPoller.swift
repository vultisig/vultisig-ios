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

    @Published private(set) var completedTransactionCount: Int = 0

    private let service = TransactionStatusService.shared
    private let recorder = TransactionHistoryRecorder.shared
    private let historyStorage = TransactionHistoryStorage.shared
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var taskTokens: [String: UUID] = [:]
    private let logger = Logger(subsystem: "com.vultisig.app", category: "tx-status-poller")

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
            while !Task.isCancelled {
                do {
                    // Ownership is re-checked before every write, not just at
                    // start. A poll that legitimately began under
                    // `trackerOutage` must not still be holding the pen when the
                    // tracker recovers — the gate has to hold for the write, and
                    // the write is what the user sees.
                    guard self?.isOwnedByTracker(txHash: txHash, pubKeyECDSA: pubKeyECDSA) != true else {
                        self?.logger.debug("Tracker regained authority mid-poll for \(txHash) — standing down")
                        break
                    }

                    let elapsed = Date().timeIntervalSince(createdAt)
                    if elapsed >= config.maxWaitTime {
                        let timeoutMessage = "timeout".localized
                        self?.recorder.updateStatus(
                            txHash: txHash,
                            pubKeyECDSA: pubKeyECDSA,
                            status: .error,
                            errorMessage: timeoutMessage
                        )
                        onUpdate(.error, timeoutMessage)
                        self?.completedTransactionCount += 1
                        break
                    }

                    let result = try await self?.service.checkTransactionStatus(
                        txHash: txHash,
                        chain: chain
                    )

                    if let result, let historyStatus = self?.mapToHistoryStatus(result) {
                        var errorMessage: String? = nil
                        if case let .failed(reason) = result.status {
                            errorMessage = reason
                        }
                        // Re-checked after the await: the status fetch is a
                        // network round-trip, and the tracker can take ownership
                        // while it is in flight.
                        guard self?.isOwnedByTracker(txHash: txHash, pubKeyECDSA: pubKeyECDSA) != true else {
                            self?.logger.debug("Tracker took authority during status fetch for \(txHash) — discarding result")
                            break
                        }
                        self?.recorder.updateStatus(
                            txHash: txHash,
                            pubKeyECDSA: pubKeyECDSA,
                            status: historyStatus,
                            errorMessage: errorMessage
                        )
                        onUpdate(historyStatus, errorMessage)
                        self?.completedTransactionCount += 1
                        break
                    }

                    try await Task.sleep(for: .seconds(config.pollInterval))
                } catch is CancellationError {
                    break
                } catch {
                    try? await Task.sleep(for: .seconds(config.pollInterval))
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

    /// Returns a terminal TransactionHistoryStatus if the result is terminal, nil if still pending.
    private func mapToHistoryStatus(_ result: TransactionStatusResult) -> TransactionHistoryStatus? {
        switch result.status {
        case .confirmed:
            return .successful
        case .failed:
            return .error
        case .notFound, .pending:
            return nil
        }
    }
}
