//
//  BackgroundTransactionPoller.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation
import OSLog
import SwiftUI

@MainActor
class BackgroundTransactionPoller: ObservableObject {
    static let shared = BackgroundTransactionPoller()

    private var pollingViewModels: [String: TransactionStatusViewModel] = [:]
    private let storage = StoredPendingTransactionStorage.shared
    private let logger = Logger(subsystem: "com.vultisig.app", category: "background-tx-poller")

    private init() {}

    /// Resume polling for all pending transactions on app launch
    func resumePendingTransactions() {
        do {
            let pendingTransactions = try storage.getAllPending()

            for transaction in pendingTransactions {
                // Check if already being polled
                guard pollingViewModels[transaction.txHash] == nil else {
                    continue
                }

                // Create view model and start polling
                let viewModel = TransactionStatusViewModel(pendingTransaction: transaction)
                pollingViewModels[transaction.txHash] = viewModel
                viewModel.startPolling()
            }

            // Cleanup old transactions
            try storage.cleanupOld()
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                logger.debug("Resume pending transactions error: \(error.localizedDescription)")
            }
        }
    }

    /// Stop polling for a specific transaction
    func stopPolling(txHash: String) {
        pollingViewModels[txHash]?.stopPolling()
        pollingViewModels.removeValue(forKey: txHash)
    }

    /// Stop all background polling
    func stopAllPolling() {
        for (_, viewModel) in pollingViewModels {
            viewModel.stopPolling()
        }
        pollingViewModels.removeAll()
    }
}
