//
//  KeysignDiscovery.swift
//  VultisigApp

import OSLog
import SwiftUI

struct KeysignDiscoveryView: View {
    let vault: Vault
    let keysignPayload: KeysignPayload?
    let customMessagePayload: CustomMessagePayload? // TODO: Switch to enum
    let transferViewModel: TransferViewModel
    let fastVaultPassword: String?
    @Binding var keysignView: KeysignView?
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel
    
    @StateObject var participantDiscovery = ParticipantDiscovery(isKeygen: false)
    @StateObject var viewModel = KeysignDiscoveryViewModel()
    
    @State var isPhoneSE = false
    @State var isLoading = false
    @State var isiOSAppOnMac = false
    @State var minWidth: CGFloat = 0
    @State var screenWidth: CGFloat = 0
    @State var screenHeight: CGFloat = 0
    @State var qrCodeImage: Image? = nil
    @State var selectedNetwork = NetworkPromptType.Internet
    @State var previewType: QRShareSheetType = .Send
    
    @State var qrSize: CGFloat = .zero
    @State var qrOutlineSize: CGFloat = .zero
    
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
                    .onChange(of: proxy.size) { oldValue, newValue in
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
        isiOSAppOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        
        if VultisigRelay.IsRelayEnabled {
            self.selectedNetwork = .Internet
        } else {
            self.selectedNetwork = .Local
        }

        viewModel.setData(
            vault: vault,
            keysignPayload: keysignPayload,
            customMessagePayload: customMessagePayload,
            participantDiscovery: participantDiscovery,
            fastVaultPassword: fastVaultPassword,
            onFastKeysign: { startKeysign() }
        )

        qrCodeImage = await viewModel.getQrImage(size: 100)
        
        if let qrCodeImage, let keysignPayload {
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
    }
    
    func getSwapFromAmount() -> String {
        let tx = swapTransaction
        
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.fromAmount) \(tx.fromCoin.ticker)"
        } else {
            return "\(tx.fromAmount) \(tx.fromCoin.ticker) (\(tx.fromCoin.chain.ticker))"
        }
    }

    func getSwapToAmount() -> String {
        let tx = swapTransaction
        
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.toAmountDecimal.description) \(tx.toCoin.ticker)"
        } else {
            return "\(tx.toAmountDecimal.description) \(tx.toCoin.ticker) (\(tx.toCoin.chain.ticker))"
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
        screenWidth = proxy.size.width
        screenHeight = proxy.size.height
        
        if screenWidth < 380 {
            isPhoneSE = true
        }
    }
}

#Preview {
    KeysignDiscoveryView(vault: Vault.example, keysignPayload: KeysignPayload.example, customMessagePayload: nil, transferViewModel: SendCryptoViewModel(), fastVaultPassword: nil, keysignView: .constant(nil), shareSheetViewModel: ShareSheetViewModel())
        .environmentObject(SettingsViewModel())
}
