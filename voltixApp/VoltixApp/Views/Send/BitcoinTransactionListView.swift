//
//  VoltixApp
//
//  Created by Enrique Souza Soares
//
import SwiftUI

struct BitcoinTransactionListView: View {
    @StateObject var bitcoinTransactionsService: BitcoinTransactionsService = BitcoinTransactionsService()
    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    
    var body: some View {
        VStack {
            List {
                if let transactions = bitcoinTransactionsService.walletData {
                    ForEach(transactions, id: \.txid) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                } else if let errorMessage = bitcoinTransactionsService.errorMessage {
                    Text("Error fetching transactions: \(errorMessage)")
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
                if let vault = appState.currentVault {
                    print("hexPubKey: \(vault.pubKeyECDSA) - hexChainCode: \(vault.hexChainCode)")
                    let result = BitcoinHelper.getBitcoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                    switch result {
                    case .success(let btc):
                        await bitcoinTransactionsService.fetchTransactions(btc.address)
                        print("address: \(btc.address)")
                    case .failure(let error):
                        print("error: \(error)")
                    }
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: BitcoinTransactionMempool
    
    var body: some View {
        VStack(alignment: .leading) {
            LabelTxHash(title: "Transaction Hash:", value: transaction.txid).padding(.vertical, 5)
            if transaction.isSent {
                ForEach(transaction.sentTo, id: \.self) { address in
                    LabelText(title: "Sent To:", value: address).padding(.vertical, 1)
                }
                LabelText(title: "Amount Sent:", value: String(Double(transaction.amountSent) / Double(100000000))).padding(.vertical, 1)
                
            } else if transaction.isReceived {
                ForEach(transaction.receivedFrom, id: \.self) { address in
                    LabelText(title: "Received From:", value: address).padding(.vertical, 1)
                }
                LabelText(title: "Amount Received:", value: String(Double(transaction.amountReceived) / Double(100000000))).padding(.vertical, 1)
            }
            LabelTextNumeric(title: "Fee:", value: String(transaction.fee)).padding(.vertical, 5)
            LabelTextNumeric(title: "Direction:", value: transaction.isSent ? "Sent" : "Received").padding(.vertical, 5)
        }
    }
    
    @ViewBuilder
    private func LabelTxHash(title: String, value: String) -> some View {
        let url = "https://mempool.space/address/\(value)"
        VStack(alignment: .leading) {
            Text(title)
                .font(Font.custom("Menlo", size: 13).weight(.bold))
            Link(destination: URL(string: url)!) {
                Text(value)
                    .font(Font.custom("Montserrat", size: 13).weight(.medium))
                    .padding(.vertical, 5)
                    .foregroundColor(Color.blue)
            }
            .buttonStyle(PlainButtonStyle()) // Use this to remove any default styling applied to the Link
        }
    }
    
    @ViewBuilder
    private func LabelText(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(Font.custom("Menlo", size: 13).weight(.bold))
            Text(value)
                .font(Font.custom("Montserrat", size: 13).weight(.medium))
                .padding(.vertical, 5)
        }
    }
    
    @ViewBuilder
    private func LabelTextNumeric(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Font.custom("Menlo", size: 13).weight(.bold))
            Spacer()
            Text(value)
                .font(Font.custom("Menlo", size: 15).weight(.ultraLight))
                .padding(.vertical, 5)
            Spacer()
        }
    }
}
