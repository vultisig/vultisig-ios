//
//  SendCryptoView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct SendCryptoView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var coinViewModel: CoinViewModel
    let group: GroupedChain
    let vault: Vault
    
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @StateObject var sendCryptoVerifyViewModel = SendCryptoVerifyViewModel()
    
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    
    var body: some View {
        ZStack {
            Background()
            view
            
            if sendCryptoViewModel.isLoading || sendCryptoVerifyViewModel.isLoading {
                loader
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(sendCryptoViewModel.currentTitle, comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        .onAppear {
            Task {
                await setData()
            }
        }
        .onChange(of: tx.coin) {
            Task {
                await setData()
            }
        }.onDisappear(){
            sendCryptoViewModel.stopMediator()
        }
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
            coinViewModel: coinViewModel,
            group: group
        )
    }
    
    var verifyView: some View {
        SendCryptoVerifyView(
            keysignPayload: $keysignPayload,
            sendCryptoViewModel: sendCryptoViewModel,
            sendCryptoVerifyViewModel: sendCryptoVerifyViewModel,
            tx: tx
        )
    }
    
    var pairView: some View {
        ZStack {
            if let keysignPayload = keysignPayload {
                KeysignDiscoveryView(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    sendCryptoViewModel: sendCryptoViewModel,
                    keysignView: $keysignView
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
    
    private func setData() async {
        await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
    }
}

#Preview {
    SendCryptoView(tx: SendTransaction(), coinViewModel:CoinViewModel(),group: GroupedChain.example, vault: Vault.example)
}
