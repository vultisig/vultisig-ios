#if os(iOS)
import Foundation
import SwiftData

/// Runs after positive broadcast evidence, independently of the Done view lifecycle.
@MainActor
enum TransactionLiveActivityBroadcast {
    static func record(hash: String, approveHash: String?, payload: KeysignPayload, vault: Vault) {
        // Every device that actually broadcasts can observe its receipt.
        let rows = TransactionBroadcastReceipt.rows(hash: hash, approveHash: approveHash, payload: payload,
                                                   pubKey: vault.pubKeyECDSA)
        rows.forEach(saveAndTrack)
    }

    static func recordApproval(hash: String, payload: KeysignPayload, vault: Vault) {
        guard let row = TransactionBroadcastReceipt.approval(hash: hash, payload: payload, pubKey: vault.pubKeyECDSA) else { return }
        saveAndTrack(row)
    }

    static func recordClaim(hash: String, coin: Coin, vault: Vault) {
        guard TransactionBroadcastReceipt.isBroadcastHash(hash) else { return }
        saveAndTrack(TransactionBroadcastReceipt.transaction(hash: hash, coin: coin, pubKey: vault.pubKeyECDSA))
    }

    private static func saveAndTrack(_ row: TransactionHistoryData) {
        do {
            try TransactionHistoryStorage.shared.save(row)
            let rows = try TransactionHistoryStorage.shared.fetchByChain(pubKeyECDSA: row.pubKeyECDSA,
                                                                        chainRawValue: row.chainRawValue)
            guard let saved = rows.first(where: { $0.txHash == row.txHash }) else { return }
            // History tracking survives ActivityKit denial or system capacity limits.
            TransactionLiveActivityCoordinator.resumeTracking(saved)
            TransactionLiveActivityCoordinator.shared.trackBroadcast(saved)
        } catch {
            Log.wallet.other.info("Live Activity could not persist the broadcast receipt")
        }
    }

    static func vaultExists(pubKey: String) throws -> Bool {
        guard let context = Storage.shared.modelContext else { throw LookupError.unavailable }
        let predicate = #Predicate<Vault> { $0.pubKeyECDSA == pubKey }
        return try context.fetchCount(FetchDescriptor(predicate: predicate)) > 0
    }
    private enum LookupError: Error { case unavailable }
}
#endif
