//
//  TransactionHistoryRoute.swift
//  VultisigApp
//

import Foundation
import SwiftData

enum TransactionHistoryRoute: Hashable {
    case list(pubKeyECDSA: String, vaultName: String, chainFilter: Chain?, initialTransactionID: UUID? = nil)

    /// Resolve the local receipt only after the app's lock and recovery gates.
    @MainActor
    static func resolveDetail(recordID: UUID, context: ModelContext) throws -> TransactionHistoryRoute? {
        let storage = TransactionHistoryStorage(modelContext: context)
        guard let row = try storage.fetch(id: recordID) else { return nil }
        let key = row.pubKeyECDSA
        let predicate = #Predicate<Vault> { $0.pubKeyECDSA == key }
        guard let vault = try context.fetch(FetchDescriptor(predicate: predicate)).first else { return nil }
        return .list(pubKeyECDSA: key, vaultName: vault.name, chainFilter: nil, initialTransactionID: row.id)
    }
}
