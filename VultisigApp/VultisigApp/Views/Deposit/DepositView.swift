//
//  DepositView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI

struct DepositView: View {
    @ObservedObject var tx: SendTransaction
    let group: GroupedChain
    let vault: Vault
    
    @StateObject var depositViewModel = DepositViewModel()
    @StateObject var depositVerifyViewModel = DepositVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationTitle(NSLocalizedString(depositViewModel.currentTitle, comment: "Deposit View title"))
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(.keyboard)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        handleBackTap()
                    } label: {
                        NavigationBlankBackButton()
                    }
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
            }
            .onDisappear(){
                depositViewModel.stopMediator()
            }
    }
    
    var content: some View {
        ZStack {
            Background()
            view
            
            if depositViewModel.isLoading || depositVerifyViewModel.isLoading {
                loader
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: depositViewModel.getProgress())
                .padding(.top, 30)
            tabView
        }
        .blur(radius: depositViewModel.isLoading ? 1 : 0)
    }
    
    var tabView: some View {
        ZStack {
            switch depositViewModel.currentIndex {
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
        DepositDetailsView(
            tx: tx,
            depositViewModel: depositViewModel,
            group: group
        )
    }
    
    var verifyView: some View {
        DepositVerifyView(
            keysignPayload: $keysignPayload,
            depositViewModel: depositViewModel,
            depositVerifyViewModel: depositVerifyViewModel,
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
                    transferViewModel: depositViewModel,
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
            if let hash = depositViewModel.hash {
                SendCryptoDoneView(vault:vault,hash: hash,explorerLink: Endpoint.getExplorerURL(chainTicker: keysignPayload?.coin.chain.ticker ?? "", txid: hash))
            } else {
                SendCryptoSigningErrorView()
            }
        }.onAppear() {
            Task{
                try await Task.sleep(for: .seconds(5)) // Back off 5s
                self.depositViewModel.stopMediator()
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
        await depositViewModel.loadGasInfoForSending(tx: tx)
    }
    
    private func handleBackTap() {
        guard depositViewModel.currentIndex>1 else {
            dismiss()
            return
        }
        
        depositViewModel.handleBackTap()
    }
}

#Preview {
    SendCryptoView(
        tx: SendTransaction(),
        group: GroupedChain.example,
        vault: Vault.example
    )
}
