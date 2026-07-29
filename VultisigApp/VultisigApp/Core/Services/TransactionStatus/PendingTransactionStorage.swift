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
    /// chain that have not been seen confirmed, as a value type safe to hand
    /// to a non-main actor.
    ///
    /// This is how the wallet tells its own unconfirmed change apart from an
    /// inbound zero-conf payment: a mempool output whose transaction hash is
    /// in this set was produced by a transaction only this vault could have
    /// signed, so no one else can replace or double-spend it.
    ///
    /// Deliberately *not* `getAllPending()`. That set answers "should the
    /// status poller still be working on this", which is a question about the
    /// poller's patience, not about the chain: it drops a transaction once the
    /// poller gives up (`timeout`) even though a low-fee transaction can sit in
    /// a mempool for far longer than any poll window. Losing ownership there
    /// would take a wallet whose confirmed inputs the send already consumed
    /// straight back to reading zero — the exact failure this lookup exists to
    /// prevent, just deferred. Only `confirmed` ends the exemption, and it ends
    /// it harmlessly: a confirmed output carries a block and needs no vouching.
    ///
    /// The set is deliberately allowed to outlive the transactions in it — a
    /// row stays non-terminal while the poller reports `notFound`, a row can be
    /// marked `failed` or `timeout` on inconclusive evidence, and the
    /// interrupted-broadcast path records a hash it could not confirm reached
    /// the network at all. None of that costs anything, because the caller
    /// intersects this set with the outputs the provider currently reports as
    /// unspent: a hash for a transaction that never landed matches no output.
    /// The one real bound is `cleanupOld`, which deletes terminal rows after a
    /// day — a transaction still unconfirmed by then loses its exemption, and
    /// its owner is looking at a stuck transaction either way.
    ///
    /// A read failure propagates rather than degrading to the empty set.
    /// Returning "nothing is pending" would be a *claim*, and in the one state
    /// this lookup exists for — the block after a send, when the wallet's only
    /// funds are its own unconfirmed change — it is the wrong one: the balance
    /// would read zero and the follow-up send would be blocked, which is the
    /// exact failure this lookup prevents, reached through a storage hiccup
    /// instead of a provider one. Thrown, the balance refresh produces no
    /// update at all and the previous balance survives (`fetchBalanceUpdate`
    /// captures the error and `applyBalanceUpdates` skips an update with no
    /// balance in it), and a send fails with the real reason instead of a
    /// misleading "not enough funds". Consistent with every other read on this
    /// type, all of which already throw.
    ///
    /// Records written before the owner was persisted carry no
    /// `pubKeyECDSA` and cannot acquire one — nothing that resumes them knows
    /// which vault signed them. They match no vault here, so their change
    /// stays unspendable until it confirms, which is exactly the behaviour
    /// this lookup replaced.
    func unconfirmedTransactionHashes(chain: Chain, vaultPubKeyECDSA: String) throws -> Set<String> {
        guard !vaultPubKeyECDSA.isEmpty else { return [] }

        let confirmed = TransactionStatus.confirmed.persistenceString
        let predicate = #Predicate<StoredPendingTransaction> { tx in
            tx.status != confirmed
        }

        do {
            let unconfirmed = try modelContext.fetch(FetchDescriptor(predicate: predicate))
            return Set(
                unconfirmed
                    .filter { $0.chain == chain && $0.pubKeyECDSA == vaultPubKeyECDSA }
                    .map(\.txHash)
            )
        } catch {
            logger.error("Failed to read pending transactions for \(chain.name): \(error.localizedDescription)")
            throw error
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
