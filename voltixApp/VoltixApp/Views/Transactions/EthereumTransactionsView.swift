//
//  EthereumTransactionsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct EthereumTransactionsView: View {
    let chain: Chain?
    let contractAddress: String?
    @EnvironmentObject var appState: ApplicationState
    @StateObject var viewModel = EthereumTransactionViewModel()
    
    var body: some View {
        view
            .task {
                guard let vault = appState.currentVault else {
                    return
                }
                await viewModel.setData(chain: chain, vault: vault)
            }
    }
    
    var view: some View {
        ZStack {
            if !viewModel.transactions.isEmpty, !viewModel.addressFor.isEmpty {
                list
            } else if viewModel.transactions.count==0 {
                VStack{
                    Spacer()
                    ErrorMessage(text: "noTransactions")
                    if let explorerUrl = viewModel.explorerByAddressUrl, let url = URL(string:explorerUrl) {
                        Link("checkExplorer",destination: url)
                            .font(.body16MenloBold)
                            .foregroundColor(.neutral0)
                            .underline()
                    }
                    Spacer()
                }
            } else {
                loader
            }
        }
    }
    
    var list: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(viewModel.transactions, id: \.hash) { transaction in
                    EthereumTransactionCell(chain:chain, transaction: transaction, myAddress: viewModel.addressFor, etherScanService: viewModel.etherScanService)
                }
            }
        }
    }
    
    var loader: some View {
        ProgressView()
            .preferredColorScheme(.dark)
    }
    
}

#Preview {
    EthereumTransactionsView(chain:Chain.Ethereum,contractAddress: nil)
}
