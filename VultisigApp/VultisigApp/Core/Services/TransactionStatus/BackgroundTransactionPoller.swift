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
            let vaults = Storage.shared.modelContext?.fetchAllVaults() ?? []

            for transaction in pendingTransactions {
                // Check if already being polled
                guard pollingViewModels[transaction.txHash] == nil else {
                    continue
                }

                // Create view model and start polling
                let vault = vaults.first { $0.pubKeyECDSA == transaction.pubKeyECDSA }
                let viewModel = TransactionStatusViewModel(
                    pendingTransaction: transaction,
                    senderAccountId: vault.flatMap(transaction.senderAccountId(in:))
                )
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
