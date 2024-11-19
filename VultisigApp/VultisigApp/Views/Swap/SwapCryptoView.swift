//
//  SwapCryptoView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoView: View {
    let fromCoin: Coin?
    let toCoin: Coin?
    let vault: Vault
    
    @StateObject var tx = SwapTransaction()
    @StateObject var swapViewModel = SwapCryptoViewModel()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    @State var keysignView: KeysignView?
    
    init(fromCoin: Coin? = nil, toCoin: Coin? = nil, vault: Vault) {
        self.fromCoin = fromCoin
        self.toCoin = toCoin
        self.vault = vault
    }
    
    var body: some View {
        content
    }
    
    var view: some View {
        VStack(spacing: 18) {
            ProgressBar(progress: swapViewModel.progress)
                .padding(.top, 12)
            
            tabView
        }
    }
    
    @ViewBuilder
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
        SwapCryptoDetailsView(tx: tx, swapViewModel: swapViewModel, vault: vault)
    }
    
    var verifyView: some View {
        SwapVerifyView(tx: tx, swapViewModel: swapViewModel, vault: vault)
    }
    
    var pairView: some View {
        ZStack {
            if let keysignPayload = swapViewModel.keysignPayload {
                KeysignDiscoveryView(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    transferViewModel: swapViewModel, 
                    fastVaultPassword: tx.fastVaultPassword.nilIfEmpty,
                    keysignView: $keysignView,
                    shareSheetViewModel: shareSheetViewModel,
                    previewType: .Swap,
                    swapTransaction: tx
                )
            } else {
                SendCryptoVaultErrorView()
            }
        }
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
                SendCryptoDoneView(
                    vault: vault, hash: hash, approveHash: swapViewModel.approveHash, 
                    chain: tx.fromCoin.chain,
                    progressLink: swapViewModel.progressLink(tx: tx, hash: hash),
                    sendTransaction: nil,
                    swapTransaction: tx
                )
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
    
    var backButton: some View {
        let isDone = swapViewModel.currentIndex==5
        
        return Button {
            swapViewModel.handleBackTap()
        } label: {
            NavigationBlankBackButton()
                .offset(x: -8)
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
}

#Preview {
    SwapCryptoView(vault: .example)
}
