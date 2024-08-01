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
    
    @ObservedObject var tx = SwapTransaction()
    @ObservedObject var swapViewModel = SwapCryptoViewModel()
    @ObservedObject var shareSheetViewModel = ShareSheetViewModel()

    @State var keysignView: KeysignView?
    
    @Environment(\.dismiss) var dismiss

    init(fromCoin: Coin? = nil, toCoin: Coin? = nil, vault: Vault) {
        self.fromCoin = fromCoin
        self.toCoin = toCoin
        self.vault = vault
    }

    var body: some View {
        content
            .task {
                swapViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault, tx: tx)
            }
            .navigationBarBackButtonHidden(true)
            .navigationTitle(NSLocalizedString("swap", comment: "SendCryptoView title"))
            .ignoresSafeArea(.keyboard)
            .toolbar {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    backButton
                }
                
                if swapViewModel.currentIndex==3 {
                    ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                        NavigationQRShareButton(title: "swap", renderedImage: shareSheetViewModel.renderedImage)
                    }
                }
            }
    }
    
    var content: some View {
        ZStack {
            Background()
            view
        }
        .onDisappear {
            swapViewModel.stopMediator()
        }
#if os(iOS)
        .onTapGesture {
            hideKeyboard()
        }
#endif
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: swapViewModel.progress)
                .padding(.top, 30)
            
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
                    keysignView: $keysignView, 
                    shareSheetViewModel: shareSheetViewModel,
                    previewTitle: "swap"
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
                    vault: vault, hash: hash, 
                    explorerLink: swapViewModel.explorerLink(tx: tx, hash: hash),
                    progressLink: swapViewModel.progressLink(tx: tx, hash: hash)
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
            handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
    
    private func handleBackTap() {
        guard swapViewModel.currentIndex>1 else {
            dismiss()
            return
        }
        
        swapViewModel.handleBackTap()
    }
}

#Preview {
    SwapCryptoView(vault: .example)
}
