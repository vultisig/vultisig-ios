//
//  SwapCryptoView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension SwapCryptoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .onLoad {
            swapViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault, tx: tx)
        }
        .task {
            await swapViewModel.loadFastVault(tx: tx, vault: vault)
        }
        .navigationBarBackButtonHidden(swapViewModel.currentIndex != 1 ? true : false)
    }

    var main: some View {
        VStack {
            headerMac
            views
        }
    }

    var headerMac: some View {
        SwapCryptoHeader(
            vault: vault,
            swapViewModel: swapViewModel,
            shareSheetViewModel: shareSheetViewModel
        )
    }

    var views: some View {
        ZStack {
            Background()
            view
        }
        .onDisappear {
            swapViewModel.stopMediator()
        }
    }
}
#endif
