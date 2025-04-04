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
    @State var selectedNetwork = NetworkPromptType.Internet
    @State var previewType: QRShareSheetType = .Send
    
    @State var qrSize: CGFloat = .zero
    @State var qrOutlineSize: CGFloat = .zero
    @State var animationVM: RiveViewModel? = nil
    @State var showDisclaimer: Bool = true
    
    var swapTransaction: SwapTransaction = SwapTransaction()
    
#if os(iOS)
    @State var orientation = UIDevice.current.orientation
#endif
    
    @Environment(\.displayScale) var displayScale
    
    let adaptiveColumns = [
        GridItem(.adaptive(minimum: 350, maximum: 500), spacing: 16)
    ]
    
    let adaptiveColumnsMac = [
        GridItem(.adaptive(minimum: 400, maximum: 800), spacing: 8)
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
        .onAppear {
            setAnimation()
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
        VStack {
            signButton
            switchLink
        }
        .background(Color.backgroundBlue)
    }
    
    var portraitContent: some View {
        ScrollView(showsIndicators: false) {
            paringQRCode
            disclaimer
            list
        }
    }
    
    var paringQRCode: some View {
        ZStack {
            animation
            qrCode
        }
        .foregroundColor(.neutral0)
        .padding()
    }
    
    var disclaimer: some View {
        ZStack {
            if selectedNetwork == .Local {
                LocalModeDisclaimer()
            } else if showDisclaimer {
                KeysignDiscoveryScanDeviceDisclaimer(showAlert: $showDisclaimer)
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
    
    var animation: some View {
        animationVM?.view()
    }
    
    private func setAnimation() {
        animationVM = RiveViewModel(fileName: "QRCodeScanned", autoPlay: true)
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
}

#Preview {
    KeysignDiscoveryView(vault: Vault.example, keysignPayload: KeysignPayload.example, customMessagePayload: nil, transferViewModel: SendCryptoViewModel(), fastVaultPassword: nil, keysignView: .constant(nil), shareSheetViewModel: ShareSheetViewModel())
        .environmentObject(SettingsViewModel())
}
