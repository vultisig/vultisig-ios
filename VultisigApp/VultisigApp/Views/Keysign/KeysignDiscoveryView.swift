//
//  KeysignDiscovery.swift
//  VultisigApp

import SwiftUI
import RiveRuntime

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
    @State var screenWidth: CGFloat = 0
    @State var screenHeight: CGFloat = 0
    @State var qrCodeImage: Image? = nil
    @State var selectedNetwork = VultisigRelay.IsRelayEnabled ? NetworkPromptType.Internet : NetworkPromptType.Local
    @State var previewType: QRShareSheetType = .Send
    
    @State var qrSize: CGFloat = .zero
    @State var qrOutlineSize: CGFloat = .zero
    @State var showDisclaimer: Bool = true
    
    var swapTransaction: SwapTransaction = SwapTransaction()
    
    @State var qrScannedAnimation: RiveViewModel? = nil
    
#if os(iOS)
    @State var orientation = UIDevice.current.orientation
#endif
    
    @Environment(\.displayScale) var displayScale
    
    let adaptiveColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 300), spacing: 16)
    ]
    
    let adaptiveColumnsMac = [
        GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 8)
    ]
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            background
            view
            
            if isLoading {
                loader
            }
        }
        .task {
            qrScannedAnimation = RiveViewModel(fileName: "QRScanner", autoPlay: true)
            await setData()
            await viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
        .onChange(of: selectedNetwork) { _, newValue in
            VultisigRelay.IsRelayEnabled = newValue == .Internet
            
            viewModel.restartParticipantDiscovery()
            Task {
                await setData()
            }
        }
    }
    
    var loader: some View {
        Loader()
    }
    
    var errorText: some View {
        SendCryptoStartErrorView(errorText: viewModel.errorMessage)
    }
    
    var list: some View {
        deviceList
    }
    
    var waitingForDevices: some View {
        ZStack(alignment: .bottom) {
            orientedContent
            button
        }
    }
    
    var button: some View {
        switchLink
            .background(Color.backgroundBlue)
    }
    
    var portraitContent: some View {
        ScrollView(showsIndicators: false) {
            paringQRCode
            disclaimer
            list
        }
    }
    
    @ViewBuilder
    var paringQRCode: some View {
        ZStack {
            qrScannedAnimation?.view()
            qrCode
        }
        .padding()
    }
    
    var disclaimer: some View {
        ZStack {
            if selectedNetwork == .Local {
                LocalModeDisclaimer()
            } 
        }
        .padding(.horizontal)
    }
    
    var listTitle: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("devices", comment: ""))
            Text("(\(viewModel.selections.count)/\(vault.getThreshold()+1))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body22BrockmannMedium)
        .foregroundColor(.neutral0)
        .padding(.bottom, 8)
        .padding(.horizontal, 24)
    }
    
    var lookingForDevices: some View {
        LookingForDevicesLoader(selectedTab: keysignState)
    }
    
    var keysignState: SetupVaultState {
        return fastVaultPassword == nil ? .secure : .fast
    }
    
    func setData() async {
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
                amount: previewType == .Send ? keysignPayload.toAmountWithTickerString : "",
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
}

#Preview {
    KeysignDiscoveryView(vault: Vault.example, keysignPayload: KeysignPayload.example, customMessagePayload: nil, transferViewModel: SendCryptoViewModel(), fastVaultPassword: nil, keysignView: .constant(nil), shareSheetViewModel: ShareSheetViewModel())
        .environmentObject(SettingsViewModel())
}
