//
//  CoinDetailView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-22.
//

import SwiftUI

struct CoinDetailView: View {
    let coin: Coin
    let group: GroupedChain
    let vault: Vault
    let viewModel: CoinViewModel
    @ObservedObject var sendTx: SendTransaction
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(coin.ticker, comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton() {
                    Task {
//                        isLoading = true
//                        
//                        for coin in group.coins {
//                            if let viewModel = coinViewModels[coin.ticker] {
//                                await viewModel.loadData(coin: coin)
//                            }
//                        }
//                        
//                        await calculateTotalBalanceInFiat()
//                        isLoading = false
                    }
                }
            }
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 20) {
                actionButtons
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 30)
        }
    }
    
    var actionButtons: some View {
        ChainDetailActionButtons(group: group, vault: vault, sendTx: sendTx)
    }
    
    var content: some View {
        VStack(spacing: 0) {
            cell
        }
        .cornerRadius(10)
    }
    
    var cell: some View {
        CoinCell(coin: coin, group: group, vault: vault, coinViewModel: viewModel)
    }
}

#Preview {
    CoinDetailView(coin: Coin.example, group: GroupedChain.example, vault: Vault.example, viewModel: CoinViewModel(), sendTx: SendTransaction())
}
