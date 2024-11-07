//
//  KeysignDiscovery.swift
//  VultisigApp

import OSLog
import SwiftUI

struct KeysignDiscoveryView: View {
    let vault: Vault
    let keysignPayload: KeysignPayload
    let transferViewModel: TransferViewModel
    let fastVaultPassword: String?
    @Binding var keysignView: KeysignView?
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel
    
    @StateObject var participantDiscovery = ParticipantDiscovery(isKeygen: false)
    @StateObject var viewModel = KeysignDiscoveryViewModel()
    
    @State var isPhoneSE = false
    @State var isLoading = false
    @State var qrCodeImage: Image? = nil
    @State var selectedNetwork = NetworkPromptType.Internet
    @State var previewType: QRShareSheetType = .Send
    
    var swapTransaction: SwapTransaction = SwapTransaction()
    
#if os(iOS)
    @State var orientation = UIDevice.current.orientation
#endif
    
    @Environment(\.displayScale) var displayScale
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    let columns = [GridItem(.adaptive(minimum: 160))]
    
    let logger = Logger(subsystem: "keysign-discovery", category: "view")
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            GeometryReader { proxy in
                Background()
                    .onAppear {
                        setData(proxy)
                    }
            }
            
            view
            
            if isLoading {
                loader
            }
        }
        .task {
            await setData()
            await viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
    }
    
    var loader: some View {
        Loader()
    }
    
    var errorText: some View {
        SendCryptoStartErrorView(errorText: viewModel.errorMessage)
    }
    
    var waitingForDevices: some View {
        ZStack {
            if participantDiscovery.peersFound.count == 0 {
                VStack(spacing: 16) {
                    orientedContent
                    bottomButtons
                }
            } else {
                ZStack(alignment: .bottom) {
                    orientedContent
                    bottomButtons
                }
            }
        }
    }
    
    var landscapeContent: some View {
        HStack(spacing: 8) {
            paringQRCode
            list
                .padding(20)
        }
    }
    
    var portraitContent: some View {
        ZStack {
            if participantDiscovery.peersFound.count == 0 {
                VStack {
                    paringQRCode
                    list
                }
            } else {
                ScrollView {
                    paringQRCode
                    list
                }
            }
        }
    }
    
    var lookingForDevices: some View {
        LookingForDevicesLoader(selectedTab: keysignState)
            .padding()
    }

    var keysignState: SetupVaultState {
        return fastVaultPassword == nil ? .secure : .fast
    }

    var networkPrompts: some View {
        NetworkPrompts(selectedNetwork: $selectedNetwork)
            .onChange(of: selectedNetwork) {
                print("selected network changed: \(selectedNetwork)")
                viewModel.restartParticipantDiscovery()
                Task{
                    await setData()
                }
            }
    }
    
    private func setData() async {
        if VultisigRelay.IsRelayEnabled {
            self.selectedNetwork = .Internet
        } else {
            self.selectedNetwork = .Local
        }

        viewModel.setData(
            vault: vault,
            keysignPayload: keysignPayload,
            participantDiscovery: participantDiscovery,
            fastVaultPassword: fastVaultPassword,
            onFastKeysign: { startKeysign() }
        )

        qrCodeImage = await viewModel.getQrImage(size: 100)
        
        guard let qrCodeImage else {
            return
        }
        
        shareSheetViewModel.render(
            qrCodeImage: qrCodeImage,
            displayScale: displayScale, 
            type: previewType,
            vaultName: vault.name,
            amount: previewType == .Send ? keysignPayload.toAmountString : "",
            toAddress: previewType == .Send ? keysignPayload.toAddress : "",
            fromAmount: previewType == .Swap ? getSwapFromAmount() : "",
            toAmount: previewType == .Swap ? getSwapToAmount() : ""
        )
    }
    
    func getSwapFromAmount() -> String {
        let tx = swapTransaction
        
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.fromAmount.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(tx.fromCoin.ticker)"
        } else {
            return "\(tx.fromAmount.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(tx.fromCoin.ticker) (\(tx.fromCoin.chain.ticker))"
        }
    }

    func getSwapToAmount() -> String {
        let tx = swapTransaction
        
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.toAmountDecimal.description.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(tx.toCoin.ticker)"
        } else {
            return "\(tx.toAmountDecimal.description.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(tx.toCoin.ticker) (\(tx.toCoin.chain.ticker))"
        }
    }
    
    func startKeysign() {
        if viewModel.isValidPeers(vault: vault) {
            keysignView = viewModel.startKeysign(vault: vault, viewModel: transferViewModel)
        }
    }
    
    
    func handleSelection(_ peer: String) {
        isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            if viewModel.selections.contains(peer) {
                // Don't remove itself
                if peer != viewModel.localPartyID {
                    viewModel.selections.remove(peer)
                }
                isLoading = false
            } else {
                viewModel.selections.insert(peer)
                isLoading = false
            }
            // startKeysign will determinate whether there is enough signers or not
            startKeysign()
        }
    }
    
    private func setData(_ proxy: GeometryProxy) {
        let screenWidth = proxy.size.width
        
        if screenWidth < 380 {
            isPhoneSE = true
        }
    }
}

#Preview {
    KeysignDiscoveryView(vault: Vault.example, keysignPayload: KeysignPayload.example, transferViewModel: SendCryptoViewModel(), fastVaultPassword: nil, keysignView: .constant(nil), shareSheetViewModel: ShareSheetViewModel())
        .environmentObject(SettingsViewModel())
}
