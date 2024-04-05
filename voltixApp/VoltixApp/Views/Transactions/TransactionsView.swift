//
//  TransactionsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct TransactionsView: View {
    let group: GroupedChain
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("transactions", comment: "Transactions"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
    
    var view: some View {
        content
            .padding(.top, 30)
    }
    
    var content: some View {
        let coin = group.coins.first
        let bitcoinCondition = coin?.chain.chainType == .UTXO
        
        return ZStack {
            if bitcoinCondition {
                UTXOTransactionsView(coin: coin)
            }  else {
                errorText
            }
        }
        .foregroundColor(.neutral0)
    }
    
    var errorText: some View {
        VStack{
            Spacer()
            ErrorMessage(text: "cannotFindTransactions")
            if let coin = group.coins.first , let explorerUrl = Endpoint.getExplorerByAddressURL(chainTicker:coin.chain.ticker,address:coin.address) {
                if let url = URL(string: explorerUrl) {
                    Link("checkExplorer",destination: url)
                        .font(.body16MenloBold)
                        .foregroundColor(.neutral0)
                        .underline()
                }
                Spacer()
            }
        }
    }
}

#Preview {
    TransactionsView(group: GroupedChain.example)
}
