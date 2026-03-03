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

    func updateStatus(txHash: String, pubKeyECDSA: String, status: TransactionHistoryStatus) throws {
        let predicate = #Predicate<TransactionHistoryItem> { item in
            item.txHash == txHash && item.pubKeyECDSA == pubKeyECDSA
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let item = try modelContext.fetch(descriptor).first else { return }

        item.statusRawValue = status.rawValue
        if status == .successful || status == .error {
            item.completedAt = Date()
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
}
