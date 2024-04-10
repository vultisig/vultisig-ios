//
//  SwapCryptoView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoView: View {

    @StateObject var tx = SwapTransaction()
    @StateObject var swapViewModel = SwapCryptoViewModel()

    @State var keysignView: KeysignView?

    let coin: Coin
    let vault: Vault

    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("swap", comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        .task {
            swapViewModel.load(tx: tx, fromCoin: coin, coins: vault.coins)
        }
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: swapViewModel.progress)
                .padding(.top, 30)
            tabView
        }
    }

    var tabView: some View {
        ZStack {
            switch swapViewModel.currentIndex {
            case 1:
                detailsView
            case 2:
                verifyView
            case 3:
                pairView
            case 4:
                keysign
            default:
                errorView
            }
        }
    }

    var detailsView: some View {
        SwapCryptoDetailsView(tx: tx, swapViewModel: swapViewModel)
    }

    var verifyView: some View {
        SwapVerifyView(tx: tx, swapViewModel: swapViewModel)
    }

    var pairView: some View {
        KeysignDiscoveryView(
            vault: vault,
            keysignPayload: swapViewModel.buildKeysignPayload(tx: tx),
            transferViewModel: swapViewModel,
            keysignView: $keysignView
        )
    }

    var keysign: some View {
        ZStack {
            if let keysignView = keysignView {
                keysignView
            } else {
                SendCryptoSigningErrorView()
            }
        }
    }

    var errorView: some View {
        SendCryptoSigningErrorView()
    }
}

#Preview {
    SwapCryptoView(coin: .example, vault: .example)
}
