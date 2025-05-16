//
//  ChainDetailActionButtons.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/5/2025.
//

#if os(iOS)
import SwiftUI
import MoonPaySdk

let moonPayApiKey = "pk_live_TF7bU9YxoJCwnwKgxY7STQjHorAQlnFE"
extension ChainDetailActionButtons{
    func showMoonPayBuy() async {
        let params = MoonPayBuyQueryParams(apiKey: moonPayApiKey)
        let helper = MoonPayHelper()
        if let vault = ApplicationState.shared.currentVault {
            params.setWalletAddresses(value: helper.getWalletAddresses(vault: vault))
        }
        
        if isChainDetail,let currency =  helper.getCurrencyFromChain(chain: group.chain,
                                                                     contractAddress: group.coins[0].contractAddress) {
            params.setCurrencyCode(value: currency)
        }
        let config = MoonPaySdkBuyConfig(
            debug: false,
            environment: MoonPayWidgetEnvironment.production,
            params: params,
            handlers: nil
        )
        
        let moonPaySdk = MoonPayiOSSdk(config: config)
        let url = moonPaySdk.generateUrlForSigning()
        let sig = await MoonPaySignatureHelper().getSignature(url:url)
        moonPaySdk.updateSignature(signature: sig)
        moonPaySdk.show(mode: MoonPayRenderingOptioniOS.WebViewOverlay())
    }
    
    func processDepositRequest(_ request: OnInitiateDepositRequestPayload){
        // TODO: Construct KeysignPayload, and bring up PeerDiscoveryView for keysign
    }
    
    func showMoonpaySell(){
        let params = MoonPaySellQueryParams(apiKey: moonPayApiKey)
        params.setQuoteCurrencyCode(value: "USD")
        let helper = MoonPayHelper()
        if let vault = ApplicationState.shared.currentVault {
            params.setRefundWalletAddresses(value: helper.getWalletAddresses(vault: vault))
        }
        if isChainDetail,let currency =  helper.getCurrencyFromChain(chain: group.chain,contractAddress: group.coins[0].contractAddress) {
            params.setBaseCurrencyCode(value: currency)
        }
        let handlers = MoonPayHandlers(
            onAuthToken: nil,
            onSwapsCustomerSetupComplete: nil,
            onUnsupportedRegion: nil,
            onKmsWalletCreated: nil,
            onLogin: nil,
            onInitiateDeposit: { payload in
                // present a view to send tx
                let response = OnInitiateDepositResponsePayload(depositId: "yourDepositId")
                return response
            },
            onTransactionCreated: { payload in
                print("onTransaction Created \(payload)")
            }
        )
        let config = MoonPaySdkSellConfig(
            debug: false,
            environment: MoonPayWidgetEnvironment.production,
            params: params,
            handlers: handlers
        )
        
        let moonPaySdk = MoonPayiOSSdk(config: config)
        moonPaySdk.show(mode: MoonPayRenderingOptioniOS.WebViewOverlay())
    }
    var buyButton: some View {
        Button {
            Task{
                await showMoonPayBuy()
            }
        } label: {
            ActionButton(title: "buy", fontColor: .turquoise600)
        }
    }
    
    var sellButton: some View {
        Button {
            showMoonpaySell()
        } label: {
            ActionButton(title: "sell", fontColor: .turquoise600)
        }
    }
}
#endif
