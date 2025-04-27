//
//  SwapCryptoView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI
import MoonPaySdk

extension SwapCryptoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            swapViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault, tx: tx)
            let params = MoonPaySwapsCustomerSetupQueryParams(apiKey: "pk_test_lcbfRHJ2a6zumnV73XKGPDESC3nFQTk",amount:0,amountCurrencyCode: "USD")
            let config = MoonPaySdkSwapsCustomerSetupConfig(
                debug: false,
                environment: MoonPayWidgetEnvironment.sandbox,
                params: params,
                handlers: nil
            )
            
            let moonPaySdk = MoonPayiOSSdk(config: config)
            moonPaySdk.show(mode: .WebViewOverlay())
        }
        .task {
            await swapViewModel.loadFastVault(tx: tx, vault: vault)
        }
        .navigationBarBackButtonHidden(swapViewModel.currentIndex != 1 ? true : false)
        .navigationTitle(NSLocalizedString(swapViewModel.currentTitle, comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
        .toolbar {
            if swapViewModel.currentIndex != 1 {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    backButton
                }
            }
            
            if swapViewModel.currentIndex==3 {
                ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                    NavigationQRShareButton(
                        vault: vault,
                        type: .Keysign,
                        renderedImage: shareSheetViewModel.renderedImage
                    )
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    var main: some View {
        views
    }
    
    var views: some View {
        ZStack {
            Background()
            view
        }
        .onDisappear {
            swapViewModel.stopMediator()
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
}
#endif
