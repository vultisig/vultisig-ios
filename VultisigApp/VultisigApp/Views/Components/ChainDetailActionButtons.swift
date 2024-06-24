//
//  ChainDetailActionButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-22.
//

import SwiftUI

struct ChainDetailActionButtons: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault
    @ObservedObject var sendTx: SendTransaction
    var coin: Coin? = nil
    
    @State var actions: [CoinAction] = []
    @State var isSendLinkActive = false
    @State var isSwapLinkActive = false
    @State var isMemoLinkActive = false
    
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
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
        .frame(maxWidth: .infinity)
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
        .navigationDestination(isPresented: $isSendLinkActive) {
            SendCryptoView(
                tx: sendTx,
                vault: vault
            )
        }
        .navigationDestination(isPresented: $isSwapLinkActive) {
            SwapCryptoView(coin: coin, vault: vault)
        }
        .navigationDestination(isPresented: $isMemoLinkActive) {
            TransactionMemoView(
                tx: sendTx,
                vault: vault
            )
        }
    }
    
    var memoButton: some View {
        Button {
            isMemoLinkActive = true
        } label: {
            ActionButton(title: "Deposit", fontColor: .turquoise600)
        }

    }
    
    var sendButton: some View {
        Button {
            isSendLinkActive = true
        } label: {
            ActionButton(title: "send", fontColor: .turquoise600)
        }
    }
    
    var swapButton: some View {
        Button {
            isSwapLinkActive = true
        } label: {
            ActionButton(title: "swap", fontColor: .persianBlue200)
        }
    }
    
    private func depositButton(_ action: CoinAction) -> some View {
        ActionButton(title: action.title, fontColor: action.color)
    }
    
    private func setData() async {
        actions = await viewModel.actionResolver.resolveActions(for: group.chain)
        
        guard let activeCoin = coin ?? group.coins.first(where: { $0.isNativeToken }) else {
            return
        }
        
        sendTx.reset(coin: activeCoin)
    }
}

#Preview {
    ChainDetailActionButtons(group: GroupedChain.example, vault: Vault.example, sendTx: SendTransaction())
        .environmentObject(CoinSelectionViewModel())
}
