//
//  EthereumTransactionsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct EthereumTransactionsView: View {
    let chain: Chain?
    @StateObject var etherScanService: EtherScanService = .shared
    @EnvironmentObject var appState: ApplicationState
    @State var contractAddress: String?
    @State var addressFor: String = ""
    @State var transactions: [EtherscanAPITransactionDetail] = []
    
    var body: some View {
        view
            .task {
                await setData()
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
                    EthereumTransactionCell(chain:chain, transaction: transaction, myAddress: addressFor, etherScanService: etherScanService)
                }
            }
        }
    }
    
    var loader: some View {
        ProgressView()
            .preferredColorScheme(.dark)
    }
    
    func setData() async {
        guard let vault = appState.currentVault else {
            return
        }
        
        switch chain?.name {
        case Chain.Ethereum.name:
            await loadETHTransactions(vault: vault)
        case Chain.BSCChain.name:
            await loadBSCTransactions(vault: vault)
        default:
            return
        }
        
    }
    func loadBSCTransactions(vault: Vault) async {
        let bnb = vault.coins.first{$0.ticker == "BNB"}
        guard let bnb else {
            return
        }
        do {
            var transactions: [EtherscanAPITransactionDetail] = []
            var forAddress: String = ""
            if let contract = contractAddress {
                (transactions, forAddress) = try await BSCService.shared.fetchBEP20Transactions(
                    forAddress: bnb.address,
                    contractAddress: contract
                )
            } else {
                (transactions, forAddress) = try await BSCService.shared.fetchTransactions(forAddress: bnb.address)
            }
            addressFor = forAddress
            self.transactions = transactions
        } catch {
            print("error: \(error)")
        }
    }
    func loadETHTransactions(vault:Vault) async{
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
    EthereumTransactionsView(chain:Chain.Ethereum)
}
