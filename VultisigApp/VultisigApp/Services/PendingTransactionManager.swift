//
//  PendingTransactionManager.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/09/25.
//

import Foundation

// MARK: - Pending Transaction Management

struct PendingTransaction: Codable {
    let txHash: String
    let address: String
    let chain: Chain
    let sequence: UInt64
    let timestamp: Date
    let isConfirmed: Bool

    init(txHash: String, address: String, chain: Chain, sequence: UInt64) {
        self.txHash = txHash
        self.address = address
        self.chain = chain
        self.sequence = sequence
        self.timestamp = Date()
        self.isConfirmed = false
    }
}

class PendingTransactionManager {
    static let shared = PendingTransactionManager()
    private var pendingTransactions: ThreadSafeDictionary<String, PendingTransaction> = ThreadSafeDictionary()
    private var pollingTasks: ThreadSafeDictionary<Chain, Task<Void, Never>> = ThreadSafeDictionary()

    private init() {
        // Don't start polling automatically - only when needed
    }

    deinit {
        for (_, task) in pollingTasks.allItems() {
            task.cancel()
        }
    }

    /// Add a pending transaction to tracking (memory only)
    func addPendingTransaction(txHash: String, address: String, chain: Chain, sequence: UInt64) {
        let transaction = PendingTransaction(txHash: txHash, address: address, chain: chain, sequence: sequence)
        self.pendingTransactions.setSync(txHash, transaction)
        print("Added pending transaction: \(txHash) for address: \(address) with sequence: \(sequence)")

        // Start polling only for this specific chain
        self.startPollingForChain(chain)
    }

    /// Check if there are any unconfirmed transactions for the given address and chain
    func hasPendingTransactions(for address: String, chain: Chain) -> Bool {
        return pendingTransactions.allItems().values.contains { transaction in
            transaction.address.lowercased() == address.lowercased() &&
            transaction.chain == chain &&
            !transaction.isConfirmed
        }
    }

    /// Get the oldest pending transaction for an address/chain combination
    func getOldestPendingTransaction(for address: String, chain: Chain) -> PendingTransaction? {
        return pendingTransactions.allItems().values
            .filter { transaction in
                transaction.address.lowercased() == address.lowercased() &&
                transaction.chain == chain &&
                !transaction.isConfirmed
            }
            .min(by: { $0.timestamp < $1.timestamp })
    }

    /// Get elapsed seconds for a transaction
    func getElapsedSeconds(for transaction: PendingTransaction) -> Int {
        let timeElapsed = Date().timeIntervalSince(transaction.timestamp)
        return Int(timeElapsed)
    }

    // MARK: - Private Methods

    /// Force check pending transactions immediately (useful for UI refresh)
    func forceCheckPendingTransactions() async {
        print("PendingTransactionManager: Force checking pending transactions")
        // Check all pending transactions across all chains
        let allPending = Array(pendingTransactions.allItems().values.filter { !$0.isConfirmed })

        for transaction in allPending {
            await checkTransactionConfirmation(transaction: transaction)
        }
    }

    /// Start polling for a specific chain
    func startPollingForChain(_ chain: Chain) {

        // Only poll for chains that support pending transaction tracking
        guard chain.supportsPendingTransactions else {
            return
        }

        // Don't start if already polling for this chain
        guard self.pollingTasks.get(chain) == nil else {
            return
        }

        // Only start if there are pending transactions for this chain
        let hasPendingForChain = self.pendingTransactions.allItems().values.contains { $0.chain == chain && !$0.isConfirmed }
        guard hasPendingForChain else {
            return
        }

        print("PendingTransactionManager: Starting polling for chain: \(chain)")

        let t = Task {
            while !Task.isCancelled {
                do {
                    await self.checkPendingTransactionsForChain(chain)

                    // Wait 10 seconds before next check
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    print("PendingTransactionManager: Polling error for \(chain): \(error)")
                    try? await Task.sleep(for: .seconds(10))
                }
            }
            print("PendingTransactionManager: Polling task cancelled for chain: \(chain)")
        }
        self.pollingTasks.setSync(chain, t)

    }

    /// Stop polling for a specific chain
    func stopPollingForChain(_ chain: Chain) {
        self.pollingTasks.get(chain)?.cancel()
        self.pollingTasks.remove(chain)
        print("PendingTransactionManager: Stopped polling for chain: \(chain)")

    }

    /// Stop all polling
    func stopAllPolling() {
        for (chain, task) in self.pollingTasks.allItems() {
            task.cancel()
            print("PendingTransactionManager: Stopped polling for chain: \(chain)")
        }
        self.pollingTasks.clear()
    }

    /// Check pending transactions for a specific chain
    private func checkPendingTransactionsForChain(_ chain: Chain) async {
        let pendingTxs = pendingTransactions.allItems()
        let chainPending = pendingTxs.values.filter {
            $0.chain == chain && !$0.isConfirmed
        }

        if !chainPending.isEmpty {
            print("PendingTransactionManager: Checking \(chainPending.count) pending transactions for \(chain)")
        }

        for transaction in chainPending {
            await checkTransactionConfirmation(transaction: transaction)
        }

        // Stop polling for this chain if no more pending transactions
        let stillHasPending = pendingTxs.values.contains {
            $0.chain == chain && !$0.isConfirmed
        }

        if !stillHasPending {
            stopPollingForChain(chain)
        }

        // Remove old transactions (older than 10 minutes)
        cleanupOldTransactions()
    }

    private func checkTransactionConfirmation(transaction: PendingTransaction) async {
        do {
            print("PendingTransactionManager: Checking status for \(transaction.txHash.prefix(8))... on \(transaction.chain)")
            let isConfirmed = try await checkTransactionStatus(txHash: transaction.txHash, chain: transaction.chain)
            print("PendingTransactionManager: Transaction \(transaction.txHash.prefix(8))... confirmed: \(isConfirmed)")

            if isConfirmed {
                pendingTransactions.remove(transaction.txHash)
                print("PendingTransactionManager: ✅ Transaction confirmed and removed: \(transaction.txHash.prefix(8))...")

                // Clear cache to force fresh nonce fetch for next transaction (background thread)
                BlockChainService.shared.clearCacheForAddress()

                // Stop polling for this chain if no more pending transactions for it
                let stillHasPendingForChain = self.pendingTransactions.allItems().values.contains {
                    $0.chain == transaction.chain && !$0.isConfirmed
                }

                if !stillHasPendingForChain {
                    self.stopPollingForChain(transaction.chain)
                }
            }

        } catch {
            print("PendingTransactionManager: ❌ Failed to check transaction status for \(transaction.txHash.prefix(8))...: \(error)")
        }
    }

    private func checkTransactionStatus(txHash: String, chain: Chain) async throws -> Bool {
        let tx = pendingTransactions.get(txHash)
        switch chain {
        case .thorChain:
            // Use nonce-based checking instead of transaction API for better reliability
            return try await checkThorchainNonceChanged(transaction: tx)
        case .mayaChain:
            // Use nonce-based checking for MayaChain
            return try await checkMayaChainNonceChanged(transaction: tx)
        case .gaiaChain, .kujira, .osmosis, .dydx, .terra, .terraClassic, .noble, .akash:
            // Use nonce-based checking for other Cosmos chains
            return try await checkCosmosNonceChanged(transaction: tx, chain: chain)
        default:
            return false
        }
    }

    /// Check if THORChain nonce has incremented (indicating transaction confirmation)
    private func checkThorchainNonceChanged(transaction: PendingTransaction?) async throws -> Bool {
        guard let transaction = transaction else {
            return false
        }

        print("PendingTransactionManager: Checking nonce for address: \(transaction.address)")
        print("PendingTransactionManager: Expected sequence > \(transaction.sequence)")

        // Fetch current account info to get latest sequence number
        let account = try await ThorchainService.shared.fetchAccountNumber(transaction.address)

        guard let currentSequenceString = account?.sequence,
              let currentSequence = UInt64(currentSequenceString) else {
            print("PendingTransactionManager: Failed to get current sequence")
            return false
        }

        print("PendingTransactionManager: Current sequence: \(currentSequence)")

        // If current sequence is greater than the transaction sequence, it means the transaction was processed
        let isConfirmed = currentSequence > transaction.sequence
        print("PendingTransactionManager: Nonce-based confirmation: \(isConfirmed)")

        return isConfirmed
    }

    /// Check if MayaChain nonce has incremented (indicating transaction confirmation)
    private func checkMayaChainNonceChanged(transaction: PendingTransaction?) async throws -> Bool {
        guard let transaction = transaction else {
            return false
        }

        print("PendingTransactionManager: Checking MayaChain nonce for address: \(transaction.address)")
        print("PendingTransactionManager: Expected sequence > \(transaction.sequence)")

        // Fetch current account info to get latest sequence number
        let account = try await MayachainService.shared.fetchAccountNumber(transaction.address)

        guard let currentSequenceString = account?.sequence,
              let currentSequence = UInt64(currentSequenceString) else {
            print("PendingTransactionManager: Failed to get current MayaChain sequence")
            return false
        }

        print("PendingTransactionManager: Current MayaChain sequence: \(currentSequence)")

        // If current sequence is greater than the transaction sequence, it means the transaction was processed
        let isConfirmed = currentSequence > transaction.sequence
        print("PendingTransactionManager: MayaChain nonce-based confirmation: \(isConfirmed)")

        return isConfirmed
    }

    /// Check if Cosmos chain nonce has incremented (indicating transaction confirmation)
    private func checkCosmosNonceChanged(transaction: PendingTransaction?, chain: Chain) async throws -> Bool {
        guard let transaction = transaction else {
            return false
        }

        print("PendingTransactionManager: Checking \(chain) nonce for address: \(transaction.address)")
        print("PendingTransactionManager: Expected sequence > \(transaction.sequence)")

        // Fetch current account info to get latest sequence number
        let service = try CosmosService.getService(forChain: chain)
        let account = try await service.fetchAccountNumber(transaction.address)

        guard let currentSequenceString = account?.sequence,
              let currentSequence = UInt64(currentSequenceString) else {
            print("PendingTransactionManager: Failed to get current \(chain) sequence")
            return false
        }

        print("PendingTransactionManager: Current \(chain) sequence: \(currentSequence)")

        // If current sequence is greater than the transaction sequence, it means the transaction was processed
        let isConfirmed = currentSequence > transaction.sequence
        print("PendingTransactionManager: \(chain) nonce-based confirmation: \(isConfirmed)")

        return isConfirmed
    }

    private func cleanupOldTransactions() {
        // Only remove transactions older than 10 minutes (safety cleanup)
        // DO NOT remove by timeout - only by confirmation
        let tenMinutesAgo = Date().addingTimeInterval(-10 * 60) // 10 minutes safety cleanup

        let veryOldTransactions = pendingTransactions.allItems().filter { _, transaction in
            transaction.timestamp < tenMinutesAgo
        }

        for (txHash, transaction) in veryOldTransactions {
            pendingTransactions.remove(txHash)
            print("Very old transaction removed (safety cleanup): \(txHash) for address: \(transaction.address)")
        }

        if !veryOldTransactions.isEmpty {
            print("Safety cleanup: removed \(veryOldTransactions.count) very old transactions (>10 minutes)")
        }
    }
}
