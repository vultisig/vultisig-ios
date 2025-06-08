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
    @StateObject var sendTx: SendTransaction
    @Binding var resetActive: Bool
    
    @State var isLoading = false
    @State var isLoadingBonds = false
    
    @State var isSendLinkActive = false
    @State var isSwapLinkActive = false
    @State var isMemoLinkActive = false
    
    var body: some View {
        content
            .navigationDestination(isPresented: $isSendLinkActive) {
                SendCryptoView(
                    tx: sendTx,
                    vault: vault,
                    coin: coin
                )
            }
            .navigationDestination(isPresented: $isSwapLinkActive) {
                SwapCryptoView(fromCoin: coin, vault: vault)
            }
            .navigationDestination(isPresented: $isMemoLinkActive) {
                FunctionCallView(
                    tx: sendTx,
                    vault: vault,
                    coin: coin
                )
            }
            .onAppear {
                sendTx.reset(coin: coin)
            }
            .task {
                if coin.isRune {
                    await fetchBondData()
                }
            }
            .onChange(of: isSendLinkActive) { oldValue, newValue in
                if newValue {
                    sendTx.reset(coin: coin)
                }
            }
            .onChange(of: isMemoLinkActive) { oldValue, newValue in
                if newValue {
                    sendTx.coin = coin
                }
            }
    }
    
    var loader: some View {
        Loader()
    }
    
    var actionButtons: some View {
        ChainDetailActionButtons(
            isChainDetail: true,
            group: group,
            isLoading: $isLoading,
            isSendLinkActive: $isSendLinkActive,
            isSwapLinkActive: $isSwapLinkActive,
            isMemoLinkActive: $isMemoLinkActive
        )
    }
    
    var cells: some View {
        VStack(spacing: 16) {
            cell
            
            if coin.isRune && coin.hasBondedNodes {
                bondCells
            } else if coin.isRune && isLoadingBonds {
                ProgressView()
                    .padding(.vertical, 8)
            }
        }
        .cornerRadius(10)
    }
    
    var cell: some View {
        CoinCell(coin: coin)
    }
    
    var bondCells: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVStack(spacing: 12) {
                ForEach(coin.bondedNodes) { node in
                    RuneBondCell(bondNode: node, coin: coin)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    func refreshData() async {
        isLoading = true
        await BalanceService.shared.updateBalance(for: coin)
        
        if coin.isRune {
            await fetchBondData()
        }
        
        isLoading = false
    }
    
    func fetchBondData() async {
        isLoadingBonds = true
        
        if let address = coin.address.isEmpty ? nil : coin.address {
            let bondedNodes = await ThorchainService.shared.fetchRuneBondNodes(address: address)
            coin.bondedNodes = bondedNodes
        }
        
        isLoadingBonds = false
    }
}

#Preview {
    CoinDetailView(coin: Coin.example, group: GroupedChain.example, vault: Vault.example, sendTx: SendTransaction(), resetActive: .constant(false))
}
