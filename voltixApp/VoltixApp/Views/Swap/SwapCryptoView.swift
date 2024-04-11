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
            await swapViewModel.load(tx: tx, fromCoin: coin, coins: vault.coins)
        }
        .alert(isPresented: swapViewModel.showError) {
            alert
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
            case 5:
                doneView
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

    var doneView: some View {
        ZStack {
            if let hash = swapViewModel.hash {
                SendCryptoDoneView(vault:vault, hash: hash, explorerLink: Endpoint.getExplorerURL(
                    chainTicker: tx.fromCoin.chain.ticker,
                    txid: hash
                ))
            } else {
                SendCryptoSigningErrorView()
            }
        }.onAppear() {
            Task {
                try await Task.sleep(for: .seconds(5))
                swapViewModel.stopMediator()
            }
        }
    }

    var errorView: some View {
        SendCryptoSigningErrorView()
    }

    var alert: Alert {
        Alert(title: Text(NSLocalizedString("error", comment: "")),
              message: Text(swapViewModel.error?.localizedDescription ?? .empty),
              dismissButton: .default(Text(NSLocalizedString("ok", comment: ""))))
    }
}

#Preview {
    SwapCryptoView(coin: .example, vault: .example)
}
