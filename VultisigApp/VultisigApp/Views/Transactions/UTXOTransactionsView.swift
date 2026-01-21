//
//  UTXOTransactionsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct UTXOTransactionsView: View {
    let coin: Coin?

    @State var tx: SendTransaction? = nil
    @StateObject var utxoTransactionsService: UTXOTransactionsService = .init()

    var body: some View {
        view
            .onAppear {
                Task {
                    await setData()
                }
            }
    }

    var view: some View {
        ZStack {
            if let transactions = utxoTransactionsService.walletData, let tx = tx {
                if transactions.count>0 {
                    getList(for: transactions, tx: tx)
                } else {
                    ErrorMessage(text: "noTransactions")
                }
            } else if let error = utxoTransactionsService.errorMessage {
                getErrorMessage(error)
            } else {
                loader
            }
        }
    }

    var loader: some View {
        ProgressView()
            .preferredColorScheme(.dark)
    }

    private func setData() async {
        guard let coin else {
            return
        }

        tx = SendTransaction(coin: coin)

        guard let tx else {
            return
        }

        if tx.coin.chain == .bitcoin {
            await utxoTransactionsService.fetchTransactions(tx.coin.address, endpointUrl: Endpoint.fetchBitcoinTransactions(tx.coin.address))
        } else if tx.coin.chain == .litecoin {
            await utxoTransactionsService.fetchTransactions(tx.coin.address, endpointUrl: Endpoint.fetchLitecoinTransactions(tx.coin.address))
        }
    }

    private func getErrorMessage(_ error: String) -> some View {
        VStack(spacing: 12) {
            ErrorMessage(text: "errorFetchingTransactions")
            Text(error)
        }
    }

    private func getList(for transactions: [UTXOTransactionMempool], tx: SendTransaction) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(transactions, id: \.txid) { transaction in
                    UTXOTransactionCell(transaction: transaction, tx: tx, utxoTransactionsService: utxoTransactionsService)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        UTXOTransactionsView(coin: Coin.example)
            .environmentObject(ApplicationState.shared)
    }
}
