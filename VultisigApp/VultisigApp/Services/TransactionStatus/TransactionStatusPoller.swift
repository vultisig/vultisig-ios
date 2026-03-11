//
//  TransactionStatusPoller.swift
//  VultisigApp
//

import Foundation

@MainActor
final class TransactionStatusPoller {
    static let shared = TransactionStatusPoller()

    private let service = TransactionStatusService.shared
    private let recorder = TransactionHistoryRecorder.shared
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var taskTokens: [String: UUID] = [:]

    private init() {}

    /// Start polling a transaction. Calls `onUpdate` on the main actor when status changes.
    func poll(
        txHash: String,
        chain: Chain,
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
                        break
                    }

                    try await Task.sleep(for: .seconds(config.pollInterval))
                } catch is CancellationError {
                    break
                } catch {
                    try? await Task.sleep(for: .seconds(config.pollInterval))
                }
            }

            await self?.cleanupTask(txHash: txHash, token: token)
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
