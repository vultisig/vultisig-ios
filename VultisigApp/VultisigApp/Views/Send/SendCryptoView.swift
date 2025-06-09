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
    
    @State var coin: Coin? = nil
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
            
            if showLoader() {
                loader
            }
        }
        .ignoresSafeArea(.keyboard)
        .onFirstAppear {
            Task {
                await setData()
                await loadGasInfo()
            }
        }
        .onChange(of: tx.coin) {
            Task {
                await loadGasInfo()
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
                    customByteFee: tx.customByteFee,
                    selectedMode: tx.feeMode
                ),
                output: self
            )
        }
    }

    var view: some View {
        VStack(spacing: 18) {
            ProgressBar(progress: sendCryptoViewModel.getProgress())
                .padding(.top, 12)
            
            tabView
        }
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
                    customMessagePayload: nil,
                    transferViewModel: sendCryptoViewModel,
                    fastVaultPassword: tx.fastVaultPassword.nilIfEmpty,
                    keysignView: $keysignView,
                    shareSheetViewModel: shareSheetViewModel,
                    previewType: .Send
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
                SendCryptoDoneView(
                    vault: vault,
                    hash: hash,
                    approveHash: nil,
                    chain: chain,
                    sendTransaction: tx,
                    swapTransaction: nil
                )
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
            Image(systemName: "fuelpump")
        }
        .foregroundColor(.neutral0)
    }

    var showFeeSettings: Bool {
        return sendCryptoViewModel.currentIndex == 1 && tx.coin.supportsFeeSettings
    }

    var errorView: some View {
        SendCryptoSigningErrorView()
    }
    
    var loader: some View {
        Loader()
    }
    
    private func setData() async {
        guard !sendCryptoViewModel.isLoading else { return }
        
        if let coin = coin {
            tx.coin = coin
            tx.fromAddress = coin.address
            tx.toAddress = deeplinkViewModel.address ?? ""
            selectedChain = nil
            self.coin = nil
        }
        
        presetData()
        
        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
    }
    
    private func loadGasInfo() async {
        guard !sendCryptoViewModel.isLoading else { return }
        await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
    }
    
    private func presetData() {
        guard let chain = selectedChain else {
            selectedChain = nil
            return
        }
        
        guard let selectedCoin = vault.coins.first(where: { $0.chain == chain}) else {
            selectedChain = nil
            return
        }
        
        if let coin = coin {
            tx.coin = coin
            tx.fromAddress = coin.address
            tx.toAddress = deeplinkViewModel.address ?? ""
            selectedChain = nil
        } else {
            tx.coin = selectedCoin
            tx.fromAddress = selectedCoin.address
            tx.toAddress = deeplinkViewModel.address ?? ""
            selectedChain = nil
        }
        
        DebounceHelper.shared.debounce {
            validateAddress(deeplinkViewModel.address ?? "")
        }
    }
    
    private func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
    
    private func showLoader() -> Bool {
        guard sendCryptoViewModel.currentIndex>1 else {
            return false
        }
        
        return sendCryptoViewModel.isLoading || sendCryptoVerifyViewModel.isLoading
    }
}

extension SendCryptoView: SendGasSettingsOutput {

    func didSetFeeSettings(chain: Chain, mode: FeeMode, gasLimit: BigInt?, byteFee: BigInt?) {
        switch chain.chainType {
        case .EVM:
            tx.customGasLimit = gasLimit
        case .UTXO:
            tx.customByteFee = byteFee
        default:
            return
        }

        tx.feeMode = mode

        Task {
            await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
        }
    }
}

#Preview {
    SendCryptoView(
        tx: SendTransaction(),
        vault: Vault.example,
        coin: .example
    )
    .environmentObject(DeeplinkViewModel())
}
