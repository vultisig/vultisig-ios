//
//  StoredPendingTransactionStorage.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation
import SwiftData

actor StoredPendingTransactionStorage {
    static let shared = StoredPendingTransactionStorage()

    private let modelContext: ModelContext

    private init() {
        self.modelContext = Storage.shared.modelContext
    }

    /// Save or update a pending transaction
    func save(
        txHash: String,
        chain: Chain,
        status: TransactionStatus,
        coinTicker: String? = nil,
        amount: String? = nil,
        toAddress: String? = nil
    ) throws {
        let config = ChainStatusConfig.config(for: chain)

        // Check if transaction already exists
        let predicate = #Predicate<StoredPendingTransaction> { tx in
            tx.txHash == txHash
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        let existing = try modelContext.fetch(descriptor).first

        if let existing = existing {
            // Update existing transaction
            existing.status = status.persistenceString
            existing.lastCheckedAt = Date()

            if case .confirmed = status {
                existing.confirmedAt = Date()
            }

            if case .failed(let reason) = status {
                existing.failureReason = reason
            }
        } else {
            // Create new transaction
            let transaction = StoredPendingTransaction(
                txHash: txHash,
                chain: chain,
                status: status.persistenceString,
                estimatedTime: config.estimatedTime,
                coinTicker: coinTicker,
                amount: amount,
                toAddress: toAddress
            )
            modelContext.insert(transaction)
        }

        try modelContext.save()
    }

    /// Get a specific pending transaction
    func get(txHash: String) throws -> StoredPendingTransaction? {
        let predicate = #Predicate<StoredPendingTransaction> { tx in
            tx.txHash == txHash
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    /// Get all non-terminal pending transactions (for background polling)
    func getAllPending() throws -> [StoredPendingTransaction] {
        let predicate = #Predicate<StoredPendingTransaction> { tx in
            tx.status == "broadcasted" || tx.status == "pending"
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Delete a transaction
    func delete(txHash: String) throws {
        if let transaction = try get(txHash: txHash) {
            modelContext.delete(transaction)
            try modelContext.save()
        }
    }

    /// Cleanup old transactions (older than 24 hours and terminal)
    func cleanupOld() throws {
        let oneDayAgo = Date().addingTimeInterval(-86400)

        let predicate = #Predicate<StoredPendingTransaction> { tx in
            tx.createdAt < oneDayAgo &&
            (tx.status == "confirmed" || tx.status == "failed" || tx.status == "timeout")
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let oldTransactions = try modelContext.fetch(descriptor)

        for transaction in oldTransactions {
            modelContext.delete(transaction)
        }

        if !oldTransactions.isEmpty {
            try modelContext.save()
            print("StoredPendingTransactionStorage: Cleaned up \(oldTransactions.count) old transactions")
        }
    }
}
