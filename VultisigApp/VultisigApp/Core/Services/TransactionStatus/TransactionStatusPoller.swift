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
    func poll(
        txHash: String,
        chain: Chain,
        createdAt: Date,
        pubKeyECDSA: String,
        onUpdate: @escaping (TransactionHistoryStatus, String?) -> Void
    ) {
        guard activeTasks[txHash] == nil else { return }

        let token = UUID()
        taskTokens[txHash] = token
        let config = ChainStatusConfig.config(for: chain)

        let task = Task { [weak self] in
            while !Task.isCancelled {
                do {
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
