//
//  CoinDetailView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-22.
//

import SwiftUI

struct CoinDetailView: View {
    let coin: Coin
    @StateObject var group: GroupedChain
    let vault: Vault
    @ObservedObject var sendTx: SendTransaction
    
    @State var isLoading = false
    
    var body: some View {
        ZStack {
            Background()
            view
            
            if isLoading {
                loader
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(coin.ticker, comment: ""))
        .onAppear {
            sendTx.reset(coin: coin)
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton() {
                    Task {
                        await refreshData()
                    }
                }
            }
        }
#endif
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
    
    var loader: some View {
        Loader()
    }
    
    var actionButtons: some View {
        ChainDetailActionButtons(group: group, vault: vault, sendTx: sendTx, coin: coin)
    }
    
    var content: some View {
        VStack(spacing: 0) {
            cell
        }
        .cornerRadius(10)
    }
    
    var cell: some View {
        CoinCell(coin: coin, group: group, vault: vault)
    }
    
    private func refreshData() async {
        isLoading = true
        await BalanceService.shared.updateBalance(for: coin)
        isLoading = false
    }
}

#Preview {
    CoinDetailView(coin: Coin.example, group: GroupedChain.example, vault: Vault.example, sendTx: SendTransaction())
}
