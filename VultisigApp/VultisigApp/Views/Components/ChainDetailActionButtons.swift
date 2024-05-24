//
//  ChainDetailActionButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-22.
//

import SwiftUI

struct ChainDetailActionButtons: View {
    let group: GroupedChain
    let vault: Vault
    @ObservedObject var sendTx: SendTransaction
    var coin: Coin? = nil
    
    @State var actions: [CoinAction] = []
    
    @EnvironmentObject var viewModel: TokenSelectionViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.rawValue) { action in
                switch action {
                case .send:
                    sendButton
                case .swap:
                    swapButton
                case .memo:
                    memoButton
                case .deposit, .bridge:
                    ActionButton(title: action.title, fontColor: action.color)
                }
            }
        }
        .frame(height: 28)
        .onAppear {
            Task {
                await setData()
            }
        }
        .onChange(of: group.id) { oldValue, newValue in
            Task {
                await setData()
            }
        }
    }
    
    var memoButton: some View {
        NavigationLink {
            TransactionMemoView(
                tx: sendTx,
                vault: vault
            )
        } label: {
            ActionButton(title: "Deposit", fontColor: .turquoise600)
        }
    }
    
    var sendButton: some View {
        NavigationLink {
            SendCryptoView(
                tx: sendTx,
                vault: vault
            )
        } label: {
            ActionButton(title: "send", fontColor: .turquoise600)
        }
    }
    
    var swapButton: some View {
        NavigationLink {
            if let coin {
                SwapCryptoView(coin: coin, coins: viewModel.allCoins, vault: vault)
            } else if let coin = group.coins.first {
                SwapCryptoView(coin: coin, coins: viewModel.allCoins, vault: vault)
            }
        } label: {
            ActionButton(title: "swap", fontColor: .persianBlue200)
        }
    }
    
    private func depositButton(_ action: CoinAction) -> some View {
        ActionButton(title: action.title, fontColor: action.color)
    }
    
    private func setData() async {
        actions = await viewModel.actionResolver.resolveActions(for: group.chain)
        
        guard let firstCoin = group.coins.first else {
            return
        }
        
        sendTx.coin = firstCoin
    }
}

#Preview {
    ChainDetailActionButtons(group: GroupedChain.example, vault: Vault.example, sendTx: SendTransaction())
        .environmentObject(TokenSelectionViewModel())
}
