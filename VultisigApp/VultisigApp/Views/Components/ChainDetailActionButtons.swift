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
    @ObservedObject var group: GroupedChain
    @ObservedObject var sendTx: SendTransaction
    
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
            if let selected = viewModel.selection.first(where: { $0.chain == group.chain }),
               let selectedCoin = group.coins.first(where: { $0.ticker.lowercased() == selected.ticker.lowercased() }) {
                sendTx.reset(coin: selectedCoin)
            }
            // Fallback to native token
            else if let nativeCoin = group.coins.first(where: { $0.isNativeToken }) {
                sendTx.reset(coin: nativeCoin)
            }

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
    
    var buyButton: some View {
        Button {
#if os(iOS)
            let handlers = MoonPayHandlers(
                onAuthToken: { data in
                    print("onAuthToken called", data)
                },
                onSwapsCustomerSetupComplete: {
                    print("onSwapsCustomerSetupComplete called")
                },
                onUnsupportedRegion: {
                    print("onUnsupportedRegion called")
                },
                onKmsWalletCreated: {
                    print("kms wallet created")
                },
                onLogin: { data in
                    print("onLogin called", data)
                },
                onInitiateDeposit: { data in
                    print("onInitiateDepositCalled")
                    let response = OnInitiateDepositResponsePayload(depositId: "yourDepositId")
                    return response
                },
                onTransactionCreated: { payload in
                    print("onTransaction Created \(payload)")
                }
            )
            let params = MoonPayBuyQueryParams(apiKey: "pk_test_lcbfRHJ2a6zumnV73XKGPDESC3nFQTk")
            
            params.setBaseCurrencyCode(value: "GBP")
            params.setBaseCurrencyAmount(value: 100)
            params.setWalletAddresses(value: ["ETH":"0x07773707BdA78aC4052f736544928b15dD31c5cc"])
            let config = MoonPaySdkBuyConfig(
                debug: false,
                environment: MoonPayWidgetEnvironment.sandbox,
                params: params,
                handlers: handlers
            )
            
            let moonPaySdk = MoonPayiOSSdk(config: config)
            moonPaySdk.show(mode: MoonPayRenderingOptioniOS.WebViewOverlay())
#endif
        } label: {
            ActionButton(title: "buy", fontColor: .turquoise600)
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
        
        guard let activeCoin = group.coins.first(where: { $0.isNativeToken }) else {
            return
        }
        
        sendTx.reset(coin: activeCoin)
    }
}

#Preview {
    ChainDetailActionButtons(
        group: GroupedChain.example,
        sendTx: SendTransaction(),
        isLoading: .constant(false),
        isSendLinkActive: .constant(false),
        isSwapLinkActive: .constant(false),
        isMemoLinkActive: .constant(false)
    )
    .environmentObject(CoinSelectionViewModel())
}
