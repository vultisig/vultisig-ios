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

    private init() {}

    /// Start polling a transaction. Calls `onUpdate` on the main actor when status changes.
    func poll(
        txHash: String,
        chain: Chain,
        pubKeyECDSA: String,
        onUpdate: @escaping (TransactionHistoryStatus) -> Void
    ) {
        guard activeTasks[txHash] == nil else { return }

        let config = ChainStatusConfig.config(for: chain)

        activeTasks[txHash] = Task {
            while !Task.isCancelled {
                do {
                    let result = try await service.checkTransactionStatus(
                        txHash: txHash,
                        chain: chain
                    )

                    if let historyStatus = mapToHistoryStatus(result) {
                        recorder.updateStatus(
                            txHash: txHash,
                            pubKeyECDSA: pubKeyECDSA,
                            status: historyStatus
                        )
                        onUpdate(historyStatus)
                        break
                    }

                    try await Task.sleep(for: .seconds(config.pollInterval))
                } catch is CancellationError {
                    break
                } catch {
                    try? await Task.sleep(for: .seconds(config.pollInterval))
                }
            }

            activeTasks.removeValue(forKey: txHash)
        }
    }

    func stopPolling(txHash: String) {
        activeTasks[txHash]?.cancel()
        activeTasks.removeValue(forKey: txHash)
    }

    func stopAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
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
