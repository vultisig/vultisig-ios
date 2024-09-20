//
//  CoinDetailView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-22.
//

import SwiftUI

struct CoinDetailView: View {
    let coin: Coin
    @ObservedObject var group: GroupedChain
    let vault: Vault
    @ObservedObject var sendTx: SendTransaction
    
    @State var isLoading = false
    
    @State var isSendLinkActive = false
    @State var isSwapLinkActive = false
    @State var isMemoLinkActive = false
    
    var body: some View {
        content
            .navigationDestination(isPresented: $isSendLinkActive) {
                SendCryptoView(
                    tx: sendTx,
                    vault: vault
                )
            }
            .navigationDestination(isPresented: $isSwapLinkActive) {
                SwapCryptoView(fromCoin: coin, vault: vault)
            }
            .navigationDestination(isPresented: $isMemoLinkActive) {
                TransactionMemoView(
                    tx: sendTx,
                    vault: vault
                )
            }
            .onAppear {
                sendTx.reset(coin: coin)
            }
            .onChange(of: isSendLinkActive) { oldValue, newValue in
                if newValue {
                    sendTx.reset(coin: coin)
                }
            }
    }
    
    var loader: some View {
        Loader()
    }
    
    var actionButtons: some View {
        ChainDetailActionButtons(
            group: group,
            sendTx: sendTx,
            isSendLinkActive: $isSendLinkActive,
            isSwapLinkActive: $isSwapLinkActive,
            isMemoLinkActive: $isMemoLinkActive
        )
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
