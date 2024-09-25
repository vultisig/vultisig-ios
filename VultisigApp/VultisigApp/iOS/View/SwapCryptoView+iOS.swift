//
//  SwapCryptoView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SwapCryptoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .onAppear {
            swapViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault, tx: tx)
        }
        .task {
            await swapViewModel.loadFastVault(tx: tx, vault: vault)
        }
        .navigationBarBackButtonHidden(swapViewModel.currentIndex != 1 ? true : false)
        .navigationTitle(NSLocalizedString(swapViewModel.currentTitle, comment: "SendCryptoView title"))
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
