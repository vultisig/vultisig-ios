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
        let bitcoinCondition = coin?.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() || coin?.chain.name.lowercased() == Chain.Litecoin.name.lowercased() || coin?.chain.name == Chain.BitcoinCash.name || coin?.chain.name == Chain.Dogecoin.name
        let ethereumCondition = coin?.chain.name == Chain.Ethereum.name || coin?.chain.name == Chain.BSCChain.name
        let isNativeCondition = !(coin?.isNativeToken ?? true)
        
        return ZStack {
            if bitcoinCondition {
                UTXOTransactionsView(coin: coin)
            } else if ethereumCondition {
                if isNativeCondition {
                    EthereumTransactionsView(chain:coin?.chain,contractAddress: coin?.contractAddress)
                } else {
                    EthereumTransactionsView(chain:coin?.chain,contractAddress: nil)
                }
            } else {
                errorText
            }
        }
        .foregroundColor(.neutral0)
    }
    
    var errorText: some View {
        ErrorMessage(text: "cannotFindTransactions")
    }
}

#Preview {
    TransactionsView(group: GroupedChain.example)
}
