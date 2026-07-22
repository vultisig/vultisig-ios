//
//  TransactionHistoryStorage.swift
//  VultisigApp
//

import Foundation
import SwiftData

@MainActor
final class TransactionHistoryStorage {
    static let shared = TransactionHistoryStorage()

    private let modelContext: ModelContext

    private init() {
        self.modelContext = Storage.shared.modelContext
    }

    // MARK: - Save

    func save(_ data: TransactionHistoryData) throws {
        guard !exists(txHash: data.txHash, pubKeyECDSA: data.pubKeyECDSA) else { return }

        let item = data.toItem()
        modelContext.insert(item)
        try modelContext.save()
    }

    // MARK: - Update Status

    func updateStatus(txHash: String, pubKeyECDSA: String, status: TransactionHistoryStatus, errorMessage: String? = nil) throws {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let item = try modelContext.fetch(descriptor).first else { return }

        item.statusRawValue = status.rawValue
        if status == .successful || status == .error {
            item.completedAt = Date()
        }
        if let errorMessage {
            item.errorMessage = errorMessage
        }
        try modelContext.save()
    }

    // MARK: - Fetch All

    func fetchAll(pubKeyECDSA: String) throws -> [TransactionHistoryData] {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { TransactionHistoryData(item: $0) }
    }

    // MARK: - Fetch by Chain

    func fetchByChain(pubKeyECDSA: String, chainRawValue: String) throws -> [TransactionHistoryData] {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.pubKeyECDSA == pubKeyECDSA && item.chainRawValue == chainRawValue
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { TransactionHistoryData(item: $0) }
    }

    // MARK: - Fetch by Type

    // MARK: - Exists Check

    func exists(txHash: String, pubKeyECDSA: String) -> Bool {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    // MARK: - Fetch by Hash

    /// Single-row lookup used by callers that want to inspect a row's metadata
    /// without iterating the full history. Returns `nil` when no matching row
    /// exists.
    func fetchTransaction(txHash: String, pubKeyECDSA: String) throws -> TransactionHistoryData? {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try modelContext.fetch(descriptor).first.map { TransactionHistoryData(item: $0) }
    }

    // MARK: - Swap-tracking metadata

    /// Persist swap-tracking metadata onto an existing row. Idempotent —
    /// overwrites whatever was there previously. Called from
    /// `TransactionHistoryRecorder` immediately after an aggregator broadcast
    /// so the matching tracking service has the data it needs to start
    /// polling.
    func attachSwapTracking(
        txHash: String,
        pubKeyECDSA: String,
        providerKind: String,
        swapId: String?,
        routeId: String?,
        broadcastHash: String,
        sourceChainId: String,
        subProvider: String?
    ) throws {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let item = try modelContext.fetch(descriptor).first else { return }

        let metadata = SwapTrackingMetadata(
            providerKind: providerKind,
            swapId: swapId,
            routeId: routeId,
            broadcastHash: broadcastHash,
            sourceChainId: sourceChainId,
            subProvider: subProvider
        )
        // Cascade-delete-owned relationship: assigning a fresh metadata row
        // here is sufficient — SwiftData drops the previous one (if any) when
        // the parent's reference is overwritten.
        item.swapTracking = metadata
        try modelContext.save()
    }

    /// Persist a poll observation. Called by a tracking service on each
    /// successful poll. Updates the `inProgress`/`successful`/`error` summary
    /// status to match the UI state so the row's existing on-chain status
    /// indicator stays in sync.
    func updateSwapTrackingStatus(
        txHash: String,
        pubKeyECDSA: String,
        latestStatus: String?,
        latestTrackingStatus: String?,
        uiStatus: SwapTrackingUiStatus,
        polledAt: Date
    ) throws {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let item = try modelContext.fetch(descriptor).first,
              let tracking = item.swapTracking else { return }

        tracking.latestStatus = latestStatus
        tracking.latestTrackingStatus = latestTrackingStatus
        tracking.lastPolledAt = polledAt
        if tracking.trackingStartedAt == nil {
            tracking.trackingStartedAt = polledAt
        }

        // Outage flag: `unknownPendingExtended` means the provider's tracker
        // has been unavailable long enough that we want native polling to
        // take over as a fallback signal. Any other UI status (transient or
        // terminal) means the tracker is answering — clear the flag so
        // native polling backs off and the tracker is authoritative again.
        tracking.trackerOutage = (uiStatus == .unknownPendingExtended)

        switch uiStatus {
        case .completed:
            item.statusRawValue = TransactionHistoryStatus.successful.rawValue
            item.completedAt = polledAt
        case .refunded, .failed, .expired, .cancelled:
            // The coarse row vocabulary is successful / error / inProgress, so
            // an order that ended without filling collapses to `error` — the
            // same bucket a refund already lands in. The row is a summary; the
            // precise outcome (and any partial fill) lives on `LimitOrder`,
            // which is authoritative for orders.
            item.statusRawValue = TransactionHistoryStatus.error.rawValue
            item.completedAt = polledAt
        case .unknownPendingExtended:
            // Tracker-outage sentinel: keep the row `.inProgress` so the
            // tx-history viewmodel can fall back to native chain polling
            // for at least the source-chain confirmation. If the tracker
            // recovers later this gets overwritten by the next successful
            // poll; if native polling reaches a terminal first that path
            // writes the coarse status itself.
            break
        case .pending, .swapping, .resting:
            // Keep `inProgress` — the on-chain row already starts there. A
            // resting order is genuinely in progress: it is waiting for a price,
            // which is the whole point of it.
            break
        }
        try modelContext.save()
    }

    /// Stamp `lastPolledAt` without changing status. Used after transient
    /// failures (5xx / network errors) so the backoff scheduler can compute
    /// the next wake-up from a stable timestamp.
    func touchSwapTrackingLastPolled(
        txHash: String,
        pubKeyECDSA: String,
        polledAt: Date
    ) throws {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let item = try modelContext.fetch(descriptor).first,
              let tracking = item.swapTracking else { return }
        tracking.lastPolledAt = polledAt
        try modelContext.save()
    }

    /// Fetch all swap rows that are mid-flight on a given provider and need
    /// polling resumed. Called from each tracking service on resume.
    func fetchInFlightSwapTracking(providerKind: String) throws -> [TransactionHistoryData] {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.swapTracking?.providerKind == providerKind
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
            .map { TransactionHistoryData(item: $0) }
            .filter { !$0.swapTrackingUiStatus.isTerminal }
    }
}
