//
//  StoredPendingTransactionStorage.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class StoredPendingTransactionStorage {
    static let shared = StoredPendingTransactionStorage()

    private let modelContext: ModelContext
    private let logger = Log.chain.store

    private init() {
        self.modelContext = Storage.shared.modelContext
    }

    /// Test seam. The singleton binds to `Storage.shared` for its lifetime, so
    /// exercising the queries against a throwaway in-memory container needs an
    /// instance of its own rather than a mutated global.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Save or update a pending transaction
    func save(
        txHash: String,
        chain: Chain,
        status: TransactionStatus,
        coinTicker: String? = nil,
        amount: String? = nil,
        toAddress: String? = nil,
        pubKeyECDSA: String? = nil
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

            // Backfill the owning vault when the record was created without it.
            // The broadcast path writes the row first and the status poller
            // starts second, so whichever arrives with the key has to be able
            // to attach it — a row with no vault is invisible to the
            // per-vault lookups that decide which unconfirmed outputs this
            // wallet may spend.
            if existing.pubKeyECDSA == nil {
                existing.pubKeyECDSA = pubKeyECDSA
            }

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
                toAddress: toAddress,
                pubKeyECDSA: pubKeyECDSA
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

    /// Hashes of the transactions this device broadcast for one vault on one
    /// chain that have not reached a terminal state, as a value type safe to
    /// hand to a non-main actor.
    ///
    /// This is how the wallet tells its own unconfirmed change apart from an
    /// inbound zero-conf payment: a mempool output whose transaction hash is
    /// in this set was produced by a transaction only this vault could have
    /// signed, so no one else can replace or double-spend it.
    ///
    /// Rows are never pruned while still pending (`cleanupOld` only deletes
    /// terminal rows older than a day), and an output that confirms no longer
    /// needs the set at all, so the answer stays complete for exactly as long
    /// as it matters. A read failure returns the empty set, which degrades
    /// spending back to confirmed-only rather than admitting anything unproven.
    ///
    /// The set is deliberately allowed to outlive the transactions in it — a
    /// row stays non-terminal while the poller reports `notFound`, and the
    /// interrupted-broadcast path records a hash it could not confirm reached
    /// the network at all. That costs nothing, because the caller intersects
    /// this set with the outputs the provider currently reports as unspent: a
    /// hash for a transaction that never landed matches no output.
    ///
    /// Records written before the owner was persisted carry no
    /// `pubKeyECDSA` and cannot acquire one — nothing that resumes them knows
    /// which vault signed them. They match no vault here, so their change
    /// stays unspendable until it confirms, which is exactly the behaviour
    /// this lookup replaced.
    func unconfirmedTransactionHashes(chain: Chain, vaultPubKeyECDSA: String) -> Set<String> {
        guard !vaultPubKeyECDSA.isEmpty else { return [] }

        do {
            let pending = try getAllPending()
            return Set(
                pending
                    .filter { $0.chain == chain && $0.pubKeyECDSA == vaultPubKeyECDSA }
                    .map(\.txHash)
            )
        } catch {
            logger.error("Failed to read pending transactions for \(chain.name): \(error.localizedDescription)")
            return []
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
            logger.info("Cleaned up \(oldTransactions.count) old transactions")
        }
    }
}
