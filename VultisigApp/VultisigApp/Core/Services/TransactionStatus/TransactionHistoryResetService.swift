//
//  TransactionHistoryResetService.swift
//  VultisigApp
//
//  Backs the global "Reset Transaction History" action in Settings ▸ Advanced.
//  It is LOCAL-ONLY: it stops polling and wipes what the app stores and shows —
//  transaction history and tracked limit orders across every vault — and
//  touches nothing on-chain. A resting limit order still exists on THORChain
//  after a reset; the user just stops tracking it here.
//

import Foundation
import OSLog
import SwiftData

@MainActor
protocol TransactionHistoryResetting {
    /// Stop all polling/tracking, then wipe all local transaction history and
    /// tracked limit orders across every vault. Destructive and irreversible.
    func resetAll()
}

@MainActor
final class TransactionHistoryResetService: TransactionHistoryResetting {
    static let shared = TransactionHistoryResetService()

    private let stopStatusPolling: @MainActor () -> Void
    private let stopBackgroundPolling: @MainActor () -> Void
    private let stopSwapTracking: @MainActor () -> Void
    private let deleteTransactionHistory: @MainActor () throws -> Void
    private let deleteLimitOrders: @MainActor () throws -> Void
    private let notifyChanged: @MainActor () -> Void
    private let logger = Logger(subsystem: "com.vultisig.app", category: "tx-history-reset")

    /// Seams default to the production singletons; tests inject fakes to assert
    /// the teardown order and that both stores are wiped.
    init(
        stopStatusPolling: @escaping @MainActor () -> Void = { TransactionStatusPoller.shared.stopAll() },
        stopBackgroundPolling: @escaping @MainActor () -> Void = { BackgroundTransactionPoller.shared.stopAllPolling() },
        stopSwapTracking: @escaping @MainActor () -> Void = { SwapTrackingRegistry.shared.stopAllTracking() },
        deleteTransactionHistory: @escaping @MainActor () throws -> Void = { try TransactionHistoryStorage.shared.deleteAll() },
        deleteLimitOrders: @escaping @MainActor () throws -> Void = { try TransactionHistoryResetService.deleteAllLimitOrders() },
        notifyChanged: @escaping @MainActor () -> Void = { NotificationCenter.default.post(name: .limitOrdersDidChange, object: nil) }
    ) {
        self.stopStatusPolling = stopStatusPolling
        self.stopBackgroundPolling = stopBackgroundPolling
        self.stopSwapTracking = stopSwapTracking
        self.deleteTransactionHistory = deleteTransactionHistory
        self.deleteLimitOrders = deleteLimitOrders
        self.notifyChanged = notifyChanged
    }

    func resetAll() {
        // STOP before DELETE. An in-flight status poll or tracker write that
        // lands after a row is deleted would recreate the row or write into a
        // deleted object — the ordering here is load-bearing, not cosmetic.
        stopStatusPolling()
        stopBackgroundPolling()
        stopSwapTracking()

        do {
            try deleteTransactionHistory()
        } catch {
            logger.error("Failed to delete transaction history: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try deleteLimitOrders()
        } catch {
            logger.error("Failed to delete limit orders: \(error.localizedDescription, privacy: .public)")
        }

        // Refresh any live tx-history surface from the now-empty tables. The
        // tx-history screen re-reads BOTH rows and orders on this notification,
        // so it never dereferences a deleted order.
        notifyChanged()
    }

    /// Delete every `LimitOrder` across all vaults.
    ///
    /// Per object, not a batch store delete, so each vault's in-memory
    /// `limitOrders` relationship stays consistent (a batch delete would leave
    /// a live `@Model` dangling for any view still holding one) and the
    /// cancel-intent fields stored on each order — `cancelBroadcastHash` /
    /// `cancelConfirmedOnChain` — go with it, leaving no orphan cancel intents.
    static func deleteAllLimitOrders() throws {
        guard let modelContext = Storage.shared.modelContext else { return }
        let orders = try modelContext.fetch(FetchDescriptor<LimitOrder>())
        guard !orders.isEmpty else { return }
        for order in orders {
            modelContext.delete(order)
        }
        try modelContext.save()
    }
}
