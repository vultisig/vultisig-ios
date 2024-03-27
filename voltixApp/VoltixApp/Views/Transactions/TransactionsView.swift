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
        ZStack(alignment: .bottom) {
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
        ScrollView {
            content
                .padding(.top, 30)
        }
    }
    
    var content: some View {
        let coin = group.coins.first
        let bitcoinCondition = coin?.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() || coin?.chain.name.lowercased() == Chain.Litecoin.name.lowercased()
        let ethereumCondition = coin?.chain.name.lowercased() == "ethereum"
        let isNativeCondition = !(coin?.isNativeToken ?? true)
        
        return ZStack {
            if bitcoinCondition {
                UTXOTransactionsView(coin: coin)
            } else if ethereumCondition {
                if isNativeCondition {
                    Erc20TransactionsView()
                } else {
                    EthereumTransactionsView()
                }
            } else {
                errorText
            }
        }
        .foregroundColor(.neutral0)
    }
    
    var errorText: some View {
        Text(NSLocalizedString("cannotFindTransactions", comment: "Cannot Find Transactions"))
            .font(.body15MenloBold)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    TransactionsView(group: GroupedChain.example)
}
