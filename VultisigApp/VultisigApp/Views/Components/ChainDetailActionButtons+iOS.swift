//
//  ChainDetailActionButtons.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/5/2025.
//

#if os(iOS)
import SwiftUI
import MoonPaySdk

extension ChainDetailActionButtons{
    func showMoonPayBuy(){
        let params = MoonPayBuyQueryParams(apiKey: "pk_test_lcbfRHJ2a6zumnV73XKGPDESC3nFQTk")
        let helper = MoonPayHelper()
        if let vault = ApplicationState.shared.currentVault {
            params.setWalletAddresses(value: helper.getWalletAddresses(vault: vault))
        }
        
        if isChainDetail,let currency =  helper.getCurrencyFromChain(chain: group.chain) {
            params.setCurrencyCode(value: currency)
        }
        let config = MoonPaySdkBuyConfig(
            debug: false,
            environment: MoonPayWidgetEnvironment.sandbox,
            params: params,
            handlers: nil
        )
        
        let moonPaySdk = MoonPayiOSSdk(config: config)
        moonPaySdk.show(mode: MoonPayRenderingOptioniOS.WebViewOverlay())
    }
    func showMoonpaySell(){
        let params = MoonPaySellQueryParams(apiKey: "pk_test_lcbfRHJ2a6zumnV73XKGPDESC3nFQTk")
        params.setQuoteCurrencyCode(value: "USD")
        let helper = MoonPayHelper()
        if let vault = ApplicationState.shared.currentVault {
            params.setRefundWalletAddresses(value: helper.getWalletAddresses(vault: vault))
        }
        if isChainDetail,let currency =  helper.getCurrencyFromChain(chain: group.chain) {
            params.setBaseCurrencyCode(value: currency)
        }
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
                print("onInitiateDepositCalled:\(data)")
                let response = OnInitiateDepositResponsePayload(depositId: "yourDepositId")
                return response
            },
            onTransactionCreated: { payload in
                print("onTransaction Created \(payload)")
            }
        )
        let config = MoonPaySdkSellConfig(
            debug: false,
            environment: MoonPayWidgetEnvironment.sandbox,
            params: params,
            handlers: handlers
        )
        
        let moonPaySdk = MoonPayiOSSdk(config: config)
        moonPaySdk.show(mode: MoonPayRenderingOptioniOS.WebViewOverlay())
    }
    var buyButton: some View {
        Button {
            showMoonPayBuy()
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
