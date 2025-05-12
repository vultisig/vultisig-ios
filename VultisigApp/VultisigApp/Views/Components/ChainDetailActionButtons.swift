//
//  ChainDetailActionButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-22.
//

import SwiftUI
#if os(iOS)
import MoonPaySdk
#endif


struct ChainDetailActionButtons: View {
    var isChainDetail: Bool
    @ObservedObject var group: GroupedChain
    @Binding var isLoading: Bool
    @Binding var isSendLinkActive: Bool
    @Binding var isSwapLinkActive: Bool
    @Binding var isMemoLinkActive: Bool
    
    @State var actions: [CoinAction] = []

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
                case .buy:
                    buyButton
                case .sell:
                    sellButton
                }
            }
        }
        .redacted(reason: isLoading ? .placeholder : [])
        .disabled(isLoading)
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
    
    
    private func setData() async {
        actions = await viewModel.actionResolver.resolveActions(for: group.chain)
    }
}

#Preview {
    ChainDetailActionButtons(
        isChainDetail:false,
        group: GroupedChain.example,
        isLoading: .constant(false),
        isSendLinkActive: .constant(false),
        isSwapLinkActive: .constant(false),
        isMemoLinkActive: .constant(false)
    )
    .environmentObject(CoinSelectionViewModel())
}
