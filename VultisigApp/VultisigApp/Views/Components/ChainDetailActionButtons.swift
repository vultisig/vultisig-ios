//
//  ChainDetailActionButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-22.
//

import SwiftUI

struct ChainDetailActionButtons: View {
    @ObservedObject var group: GroupedChain
    @ObservedObject var sendTx: SendTransaction
    
    @State var actions: [CoinAction] = []
    @Binding var isSendLinkActive: Bool
    @Binding var isSwapLinkActive: Bool
    @Binding var isMemoLinkActive: Bool

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
                    ActionButton(title: "function", fontColor: action.color)
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
    }
    
    var memoButton: some View {
        Button {
            isMemoLinkActive = true
        } label: {
            ActionButton(title: "function", fontColor: .turquoise600)
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
        
        guard let activeCoin = group.coins.first(where: { $0.isNativeToken }) else {
            return
        }
        
        sendTx.reset(coin: activeCoin)
    }
}

#Preview {
    ChainDetailActionButtons(group: GroupedChain.example, sendTx: SendTransaction(), isSendLinkActive: .constant(false),isSwapLinkActive: .constant(false), isMemoLinkActive: .constant(false))
        .environmentObject(CoinSelectionViewModel())
}
