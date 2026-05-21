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

    func fetchByType(pubKeyECDSA: String, type: TransactionHistoryType) throws -> [TransactionHistoryData] {
        let typeValue = type.rawValue
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.pubKeyECDSA == pubKeyECDSA && item.typeRawValue == typeValue
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { TransactionHistoryData(item: $0) }
    }

    // MARK: - Exists Check

    func exists(txHash: String, pubKeyECDSA: String) -> Bool {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    // MARK: - SwapKit tracking

    /// Persist the SwapKit-track-key fields onto an existing row. Idempotent
    /// — overwrites whatever was there previously. Called from
    /// `TransactionHistoryRecorder` immediately after a SwapKit broadcast so
    /// the tracking service has the data it needs to start polling.
    func attachSwapKitTracking(
        txHash: String,
        pubKeyECDSA: String,
        swapId: String?,
        routeId: String?,
        broadcastHash: String,
        sourceChainId: String,
        provider: String?
    ) throws {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let item = try modelContext.fetch(descriptor).first else { return }

        item.swapKitSwapId = swapId
        item.swapKitRouteId = routeId
        item.swapKitBroadcastHash = broadcastHash
        item.swapKitSourceChainId = sourceChainId
        item.swapKitProvider = provider
        try modelContext.save()
    }

    /// Persist a poll observation. Called by the tracking service on each
    /// successful `/track` response. Updates the `inProgress`/`successful`/
    /// `error` summary status to match the SwapKit UI state so the row's
    /// existing on-chain status indicator stays in sync.
    func updateSwapKitStatus(
        txHash: String,
        pubKeyECDSA: String,
        latestStatus: String?,
        latestTrackingStatus: String?,
        uiStatus: SwapKitUiStatus,
        polledAt: Date
    ) throws {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let item = try modelContext.fetch(descriptor).first else { return }

        item.swapKitLatestStatus = latestStatus
        item.swapKitLatestTrackingStatus = latestTrackingStatus
        item.swapKitLastPolledAt = polledAt
        if item.swapKitTrackingStartedAt == nil {
            item.swapKitTrackingStartedAt = polledAt
        }

        // Outage flag: `unknownPendingExtended` means `/track` has been
        // unavailable long enough that we want native polling to take over
        // as a fallback signal. Any other UI status (including transient
        // `pending`/`swapping` or terminal `completed`/`refunded`/`failed`)
        // means `/track` is answering — clear the flag so native polling
        // backs off and `/track` is authoritative again.
        item.swapKitTrackerOutage = (uiStatus == .unknownPendingExtended)

        switch uiStatus {
        case .completed:
            item.statusRawValue = TransactionHistoryStatus.successful.rawValue
            item.completedAt = polledAt
        case .refunded, .failed:
            item.statusRawValue = TransactionHistoryStatus.error.rawValue
            item.completedAt = polledAt
        case .unknownPendingExtended:
            // Tracker-outage sentinel: keep the row `.inProgress` so the
            // tx-history viewmodel can fall back to native chain polling
            // for at least the source-chain confirmation. If `/track`
            // recovers later this gets overwritten by the next successful
            // poll; if native polling reaches a terminal first that path
            // writes the coarse status itself.
            break
        case .pending, .swapping:
            // Keep `inProgress` — the on-chain row already starts there.
            break
        }
        try modelContext.save()
    }

    /// Stamp `lastPolledAt` without changing status. Used after transient
    /// failures (5xx / network errors) so the backoff scheduler can compute
    /// the next wake-up from a stable timestamp.
    func touchSwapKitLastPolled(
        txHash: String,
        pubKeyECDSA: String,
        polledAt: Date
    ) throws {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let item = try modelContext.fetch(descriptor).first else { return }
        item.swapKitLastPolledAt = polledAt
        try modelContext.save()
    }

    /// Fetch all swap rows that are mid-flight on SwapKit and need polling
    /// resumed (called from the tx-history viewmodel `onAppear`, the
    /// done-screen handoff, and the ScenePhase observer on `.active`).
    func fetchInFlightSwapKitSwaps() throws -> [TransactionHistoryData] {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.swapKitBroadcastHash != nil && item.swapKitSourceChainId != nil
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
            .map { TransactionHistoryData(item: $0) }
            .filter { !$0.swapKitUiStatus.isTerminal }
    }
}
