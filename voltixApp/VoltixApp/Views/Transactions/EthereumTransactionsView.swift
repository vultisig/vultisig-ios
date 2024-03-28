//
//  EthereumTransactionsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct EthereumTransactionsView: View {
    @StateObject var etherScanService: EtherScanService = .shared
    @EnvironmentObject var appState: ApplicationState
    @State var contractAddress: String?
    @State var addressFor: String = ""
    @State var transactions: [EtherscanAPITransactionDetail] = []
    
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
            if !transactions.isEmpty, !addressFor.isEmpty {
                list
            } else if transactions.count==0 {
                ErrorMessage(text: "noTransactions")
            } else {
                loader
            }
        }
    }
    
    var list: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(transactions, id: \.hash) { transaction in
                    EthereumTransactionCell(transaction: transaction, myAddress: addressFor, etherScanService: etherScanService)
                }
            }
        }
    }
    
    var loader: some View {
        ProgressView()
            .preferredColorScheme(.dark)
    }
    
    private func setData() async {
        guard let vault = appState.currentVault else {
            return
        }
        
        let eth = vault.coins.first{$0.ticker == "ETH"}
        guard let eth else {
            return
        }
        
        do {
            var transactions: [EtherscanAPITransactionDetail] = []
            var forAddress: String = ""
            
            if let contract = contractAddress {
                (transactions, forAddress) = try await etherScanService.fetchERC20Transactions(
                    forAddress: eth.address,
                    contractAddress: contract
                )
            } else {
                (transactions, forAddress) = try await etherScanService.fetchTransactions(forAddress: eth.address)
            }
            
            addressFor = forAddress
            self.transactions = transactions
        } catch {
            print("error: \(error)")
        }
    }
}

#Preview {
    EthereumTransactionsView()
}
