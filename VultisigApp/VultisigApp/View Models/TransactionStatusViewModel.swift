//
//  TransactionStatusViewModel.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation
import OSLog
import SwiftUI

@MainActor
class TransactionStatusViewModel: ObservableObject {
    @Published var status: TransactionStatus = .broadcasted(estimatedTime: "")

    private let txHash: String
    private let chain: Chain
    private let config: ChainStatusConfig
    private let service = TransactionStatusService.shared
    private let storage = StoredPendingTransactionStorage.shared
    private let logger = Logger(subsystem: "com.vultisig.app", category: "tx-status-viewmodel")

    // Optional metadata for persistence
    private let coinTicker: String?
    private let amount: String?
    private let toAddress: String?
    private let pubKeyECDSA: String?

    private var pollingTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var startTime: Date?

    init(
        txHash: String,
        chain: Chain,
        coinTicker: String? = nil,
        amount: String? = nil,
        toAddress: String? = nil,
        pubKeyECDSA: String? = nil
    ) {
        self.txHash = txHash
        self.chain = chain
        self.config = ChainStatusConfig.config(for: chain)
        self.coinTicker = coinTicker
        self.amount = amount
        self.toAddress = toAddress
        self.pubKeyECDSA = pubKeyECDSA

        // Set initial state
        self.status = .broadcasted(estimatedTime: config.estimatedTime)
    }

    /// Initialize from SwiftData (resume existing transaction)
    init(pendingTransaction: StoredPendingTransaction) {
        self.txHash = pendingTransaction.txHash
        self.chain = pendingTransaction.chain
        self.config = ChainStatusConfig.config(for: pendingTransaction.chain)
        self.coinTicker = pendingTransaction.coinTicker
        self.amount = pendingTransaction.amount
        self.toAddress = pendingTransaction.toAddress
        self.pubKeyECDSA = pendingTransaction.pubKeyECDSA

        // Restore status from persistence
        self.status = Self.statusFromString(
            pendingTransaction.status,
            estimatedTime: pendingTransaction.estimatedTime,
            failureReason: pendingTransaction.failureReason
        )

        // Calculate elapsed time from creation
        self.startTime = pendingTransaction.createdAt
    }

    /// Start polling for transaction status
    func startPolling() {
        guard pollingTask == nil else { return }

        if startTime == nil {
            startTime = Date()
        }

        // Save initial state to SwiftData
        Task { @MainActor in
            try? storage.save(
                txHash: txHash,
                chain: chain,
                status: status,
                coinTicker: coinTicker,
                amount: amount,
                toAddress: toAddress,
                pubKeyECDSA: pubKeyECDSA
            )
        }

        // Start polling task
        pollingTask = Task { @MainActor in
            while !Task.isCancelled && !status.isTerminal {
                do {
                    let result = try await service.checkTransactionStatus(
                        txHash: txHash,
                        chain: chain
                    )

                    updateStatus(from: result)

                    // Exit if terminal state reached
                    if status.isTerminal {
                        break
                    }

                    // Check max wait timeout
                    if let start = startTime,
                       Date().timeIntervalSince(start) > config.maxWaitTime {
                        status = .timeout
                        saveStatus()
                        break
                    }

                    // Wait for next poll interval
                    try await Task.sleep(for: .seconds(config.pollInterval))

                } catch is CancellationError {
                    break
                } catch {
                    logger.error("Polling error: \(error)")
                    // On error, retry after poll interval
                    try? await Task.sleep(for: .seconds(config.pollInterval))
                }
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func updateStatus(from result: TransactionStatusResult) {
        let previousStatus = status

        switch result.status {
        case .notFound, .pending:
            // Transition from broadcasted to pending
            if case .broadcasted = status {
                status = .pending
            }

        case .confirmed:
            status = .confirmed

        case .failed(let reason):
            status = .failed(reason: reason)
        }

        // Save to SwiftData if status changed
        if previousStatus != status {
            saveStatus()

            // Update transaction history status on terminal states
            if let pubKeyECDSA, status.isTerminal {
                let historyStatus: TransactionHistoryStatus = (status == .confirmed) ? .successful : .error
                TransactionHistoryRecorder.shared.updateStatus(
                    txHash: txHash,
                    pubKeyECDSA: pubKeyECDSA,
                    status: historyStatus
                )
            }
        }
    }

    private func saveStatus() {
        do {
            try storage.save(
                txHash: txHash,
                chain: chain,
                status: status,
                coinTicker: coinTicker,
                amount: amount,
                toAddress: toAddress,
                pubKeyECDSA: pubKeyECDSA
            )
        } catch {
            logger.error("Failed to save status: \(error)")
        }
    }

    private static func statusFromString(
        _ statusString: String,
        estimatedTime: String,
        failureReason: String?
    ) -> TransactionStatus {
        switch statusString {
        case "broadcasted":
            return .broadcasted(estimatedTime: estimatedTime)
        case "pending":
            return .pending
        case "confirmed":
            return .confirmed
        case "failed":
            return .failed(reason: failureReason ?? "Unknown error")
        case "timeout":
            return .timeout
        default:
            return .broadcasted(estimatedTime: estimatedTime)
        }
    }

    deinit {
        pollingTask?.cancel()
        timerTask?.cancel()
    }
}
