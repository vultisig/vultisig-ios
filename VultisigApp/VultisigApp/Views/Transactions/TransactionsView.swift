//
//  TransactionsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct TransactionsView: View {
    @ObservedObject var group: GroupedChain
    
    var body: some View {
        content
    }
    
    var view: some View {
        states
            .padding(.top, 30)
    }
    
    var states: some View {
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
