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
        ZStack {
            Background()
            main
            
            if isLoading {
                loader
            }
        }
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
#if os(iOS)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(coin.ticker, comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationRefreshButton() {
                    Task {
                        await refreshData()
                    }
                }
            }
        }
#endif
        .onAppear {
            sendTx.reset(coin: coin)
        }
        .onChange(of: isSendLinkActive) { oldValue, newValue in
            if newValue {
                sendTx.reset(coin: coin)
            }
        }
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        CoinDetailHeader(title: group.name, refreshData: refreshData)
            .padding(.horizontal, 40)
            .padding(.top, 8)
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 20) {
                actionButtons
                content
            }
            .padding(.horizontal, 16)
#if os(iOS)
            .padding(.vertical, 30)
#elseif os(macOS)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
#endif
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
