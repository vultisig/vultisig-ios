//
//  SendCryptoView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI
import BigInt

struct SendCryptoView: View {
    @ObservedObject var tx: SendTransaction
    let vault: Vault
    
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    @StateObject var sendCryptoVerifyViewModel = SendCryptoVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    @State var selectedChain: Chain? = nil
    @State var settingsPresented = false

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            Background()
            main
            
            if sendCryptoViewModel.isLoading || sendCryptoVerifyViewModel.isLoading {
                loader
            }
        }
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
        .navigationBarBackButtonHidden(sendCryptoViewModel.currentIndex != 1 ? true : false)
        .sheet(isPresented: $settingsPresented) {
            SendGasSettingsView(
                viewModel: SendGasSettingsViewModel(
                    coin: tx.coin,
                    vault: vault,
                    gasLimit: tx.gasLimit,
                    selectedMode: tx.feeMode
                ),
                output: self
            )
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
                    fastVaultPassword: tx.fastVaultPassword.nilIfEmpty,
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
            if let hash = sendCryptoViewModel.hash, let chain = keysignPayload?.coin.chain {
                SendCryptoDoneView(vault: vault, hash: hash, approveHash: nil, chain: chain)
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

    var settingsButton: some View {
        Button {
            settingsPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .foregroundColor(.neutral0)
    }

    var showFeeSettings: Bool {
        return sendCryptoViewModel.currentIndex == 1 && tx.coin.chainType == .EVM
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
            sendCryptoViewModel.handleBackTap()
        } label: {
            NavigationBlankBackButton()
                .offset(x: -8)
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
    
    private func setData() async {
        presetData()
        await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
    }
    
    private func presetData() {
        guard let chain = selectedChain else {
            selectedChain = nil
            return
        }
        
        guard let selectedCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
            selectedChain = nil
            return
        }
        
        tx.coin = selectedCoin
        tx.toAddress = deeplinkViewModel.address ?? ""
        selectedChain = nil
        DebounceHelper.shared.debounce {
            validateAddress(deeplinkViewModel.address ?? "")
        }
    }
    
    private func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
}

extension SendCryptoView: SendGasSettingsOutput {

    func didSetFeeSettings(gasLimit: BigInt, mode: FeeMode) {
        tx.customGasLimit = gasLimit
        tx.feeMode = mode

        Task {
            await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
        }
    }
}

#Preview {
    SendCryptoView(
        tx: SendTransaction(),
        vault: Vault.example
    )
    .environmentObject(DeeplinkViewModel())
}
