import SwiftData
import SwiftUI

/// Resolves the opaque ID across local vaults after ContentView's passcode/recovery gate.
struct TransactionActivityDetailScreen: View {
    let recordID: UUID
    @Environment(\.modelContext) private var context
    @State private var transaction: TransactionHistoryData?

    var body: some View {
        Group {
            if let transaction {
                TransactionHistoryDetailSheet(transaction: transaction, presentation: .screen)
            } else {
                Screen {
                    Text("transactionActivityUnavailable".localized)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
            }
        }
        .task {
            reload()
            guard let transaction else { return }
            if transaction.type == .swap,
               transaction.swapTracking?.providerKind == SwapKitTrackingService.providerKind {
                await SwapKitTrackingService.shared.forceRefresh(tx: transaction)
            } else if transaction.type == .send {
                TransactionStatusPoller.shared.poll(tx: transaction) { _, _ in reload() }
            }
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: TransactionHistoryActivityEvent.notification)) { _ in reload() }
    }

    private func reload() {
        do {
            let storage = TransactionHistoryStorage(modelContext: context)
            guard let row = try storage.fetch(id: recordID) else { transaction = nil; return }
            let key = row.pubKeyECDSA
            let predicate = #Predicate<Vault> { $0.pubKeyECDSA == key }
            guard try context.fetchCount(FetchDescriptor(predicate: predicate)) > 0 else { transaction = nil; return }
            transaction = row
        } catch {
            // Keep a previously resolved receipt during a transient store error;
            // the next history event retries. Only a successful missing lookup clears it.
            return
        }
    }
}
