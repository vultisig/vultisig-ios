import SwiftUI

struct BitcoinTransactionListView: View {
    @StateObject var bitcoinTransactionsService = BitcoinTransactionsService()
    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    
    var body: some View {
        VStack {
            List {
                if let transactions = bitcoinTransactionsService.walletData?.txrefs {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                } else if let errorMessage = bitcoinTransactionsService.errorMessage {
                    Text("Error fetching transactions: \(errorMessage)")
                } else if bitcoinTransactionsService.walletData?.address != nil {
                    VStack(alignment: .leading) {
                        Text("No transactions found yet for the address: ")
                            .font(Font.custom("Menlo", size: 13).weight(.bold))
                        Text(bitcoinTransactionsService.walletData?.address ?? "")
                            .font(Font.custom("Montserrat", size: 13).weight(.medium))
                            .padding(.vertical, 5)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Transactions")
            .navigationBarBackButtonHidden()
            .modifier(InlineNavigationBarTitleModifier())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
            }
            .task {
                if appState.currentVault?.segwitBitcoinAddress != nil {
                    await bitcoinTransactionsService.fetchTransactions(for: appState.currentVault?.segwitBitcoinAddress ?? "")
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: TransactionRef
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Transaction Hash: \(transaction.txHash ?? "N/A")")
            Text("Value: \(transaction.value ?? 0) satoshis")
            Text("Confirmations: \(transaction.confirmations ?? 0)")
        }
    }
}

#Preview{
    BitcoinTransactionListView(presentationStack: .constant([]))
}
