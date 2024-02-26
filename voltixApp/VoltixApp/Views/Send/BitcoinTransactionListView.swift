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
                    let helper = try? CoinFactory.createCoinHelper(for: "BTC")
                    let result = helper?.getCoinDetails(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                    switch result {
                        case .success(let btc):
                                // "bc1qj9q4nsl3q7z6t36un08j6t7knv5v3cwnnstaxu"
                                print(btc.address)
                                await bitcoinTransactionsService.fetchTransactions(btc.address)
                                //await bitcoinTransactionsService.fetchTransactions("bc1qj9q4nsl3q7z6t36un08j6t7knv5v3cwnnstaxu")
                        case .failure(let error):
                            print("error: \(error)")
                        default:
                            print("ERROR")
                    }
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: BitcoinTransactionMempool
    
    var body: some View {
        Section{
            VStack(alignment: .leading) {
                LabelTxHash(title: "TX ID:".uppercased(), value: transaction.txid, isSent: transaction.isSent)
                    .padding(.vertical, 5)
                Divider() // Adds a horizontal line
                
                if transaction.isSent {
                    ForEach(transaction.sentTo, id: \.self) { address in
                        LabelText(title: "To:".uppercased(), value: address)
                            .padding(.vertical, 1)
                    }
                    Divider() // Adds a horizontal line
                    LabelTextNumeric(title: "Amount:".uppercased(), value: String(Double(transaction.amountSent) / Double(100000000)))
                        .padding(.vertical, 1)
                } else if transaction.isReceived {
                    ForEach(transaction.receivedFrom, id: \.self) { address in
                        LabelText(title: "From:".uppercased(), value: address)
                            .padding(.vertical, 1)
                    }
                    Divider() // Adds a horizontal line
                    LabelTextNumeric(title: "Amount:".uppercased(), value: String(Double(transaction.amountReceived) / Double(100000000)))
                        .padding(.vertical, 1)
                }
                
                if transaction.opReturnData != nil {
                    Divider() // Adds a horizontal line
                    LabelText(title: "MEMO:".uppercased(), value: transaction.opReturnData ?? "")
                        .padding(.vertical, 1)
                }
                
                Divider() // Adds a horizontal line
                LabelTextNumeric(title: "Fee:", value: String(transaction.fee))
                    .padding(.vertical, 5)
//                Divider() // Adds a horizontal line
//                LabelTextNumeric(title: "Direction:", value: transaction.isSent ? "Sent" : "Received")
//                    .padding(.vertical, 5)
            }
        }
    }
    
    
    @ViewBuilder
    private func LabelTxHash(title: String, value: String, isSent: Bool) -> some View {
        let url = "https://mempool.space/tx/\(value)"
        VStack(alignment: .leading) {
            HStack{
                Image(systemName: isSent ? "arrowtriangle.up.square" : "arrowtriangle.down.square")
                    .resizable()
                    .frame(width: 20, height: 20)
                
                Text(title)
                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                
            }
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
                .font(Font.custom("Menlo", size: 20).weight(.bold))
            Text(value)
                .font(Font.custom("Montserrat", size: 13).weight(.medium))
                .padding(.vertical, 5)
        }
    }
    
    @ViewBuilder
    private func LabelTextNumeric(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Font.custom("Menlo", size: 20).weight(.bold))
            Spacer()
            Text(value)
                .font(Font.custom("Menlo", size: 30).weight(.ultraLight))
                .padding(.vertical, 5)
        }
    }
}
