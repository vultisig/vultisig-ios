//
//  BackgroundTransactionPoller.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation
import SwiftUI
import OSLog

@MainActor
class BackgroundTransactionPoller: ObservableObject {
    static let shared = BackgroundTransactionPoller()

    private var pollingViewModels: [String: TransactionStatusViewModel] = [:]
    private let storage = StoredPendingTransactionStorage.shared

    private init() {}

    /// Resume polling for all pending transactions on app launch
    func resumePendingTransactions() {
        do {
            let pendingTransactions = try storage.getAllPending()

            Log.chain.service.debug("Found \(pendingTransactions.count) pending transactions")

            for transaction in pendingTransactions {
                // Check if already being polled
                guard pollingViewModels[transaction.txHash] == nil else {
                    continue
                }

                // Create view model and start polling
                let viewModel = TransactionStatusViewModel(pendingTransaction: transaction)
                pollingViewModels[transaction.txHash] = viewModel
                viewModel.startPolling()

                Log.chain.service.debug("Resumed polling for \(String(transaction.txHash.prefix(8)), privacy: .public)...")
            }

            // Cleanup old transactions
            try storage.cleanupOld()
        } catch {
            Log.chain.service.error("Error resuming transactions: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stop all background polling
    func stopAllPolling() {
        for (_, viewModel) in pollingViewModels {
            viewModel.stopPolling()
        }
        pollingViewModels.removeAll()
    }
}
