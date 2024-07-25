//
//  SendCryptoView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct SendCryptoView: View {
    @ObservedObject var tx: SendTransaction
    let vault: Vault
    
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    @StateObject var sendCryptoVerifyViewModel = SendCryptoVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationTitle(NSLocalizedString(sendCryptoViewModel.currentTitle, comment: "SendCryptoView title"))
            .ignoresSafeArea(.keyboard)
            .onAppear {
                Task {
                    await setData()
                }
            }
            .onChange(of: tx.coin) {
                Task {
                    await setData()
                }
            }
            .onDisappear(){
                sendCryptoViewModel.stopMediator()
            }
            .toolbar {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    backButton
                }
                
                if sendCryptoViewModel.currentIndex==3 {
                    ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                        NavigationQRShareButton(title: "joinKeygen", renderedImage: shareSheetViewModel.renderedImage)
                    }
                }
            }

    }
    
    var content: some View {
        ZStack {
            Background()
            view
            
            if sendCryptoViewModel.isLoading || sendCryptoVerifyViewModel.isLoading {
                loader
            }
        }
#if os(iOS)
        .onTapGesture {
            hideKeyboard()
        }
#endif
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: sendCryptoViewModel.getProgress())
                .padding(.top, 30)
            
            tabView
        }
        .blur(radius: sendCryptoViewModel.isLoading ? 1 : 0)
    }
    
    var tabView: some View {
        ZStack {
            switch sendCryptoViewModel.currentIndex {
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
        .frame(maxHeight: .infinity)
    }
    
    var detailsView: some View {
        SendCryptoDetailsView(
            tx: tx,
            sendCryptoViewModel: sendCryptoViewModel,
            vault: vault
        )
    }
    
    var verifyView: some View {
        SendCryptoVerifyView(
            keysignPayload: $keysignPayload,
            sendCryptoViewModel: sendCryptoViewModel,
            sendCryptoVerifyViewModel: sendCryptoVerifyViewModel,
            tx: tx, 
            vault: vault
        )
    }
    
    var pairView: some View {
        ZStack {
            if let keysignPayload = keysignPayload {
                KeysignDiscoveryView(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    transferViewModel: sendCryptoViewModel,
                    keysignView: $keysignView,
                    shareSheetViewModel: shareSheetViewModel,
                    previewTitle: "send"
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
            if let hash = sendCryptoViewModel.hash {
                SendCryptoDoneView(vault:vault,hash: hash,explorerLink: Endpoint.getExplorerURL(chainTicker: keysignPayload?.coin.chain.ticker ?? "", txid: hash))
            } else {
                SendCryptoSigningErrorView()
            }
        }.onAppear() {
            Task{
                try await Task.sleep(for: .seconds(5)) // Back off 5s
                self.sendCryptoViewModel.stopMediator()
            }
        }
    }
    
    var errorView: some View {
        SendCryptoSigningErrorView()
    }
    
    var loader: some View {
        Loader()
    }
    
    var backButton: some View {
        let isDone = sendCryptoViewModel.currentIndex==5
        
        return Button {
            handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
    
    private func setData() async {
        await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
    }
    
    private func handleBackTap() {
        guard sendCryptoViewModel.currentIndex>1 else {
            dismiss()
            return
        }
        
        sendCryptoViewModel.handleBackTap()
    }
}

#Preview {
    SendCryptoView(
        tx: SendTransaction(),
        vault: Vault.example
    )
}
