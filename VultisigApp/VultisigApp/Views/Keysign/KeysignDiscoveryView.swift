//
//  KeysignDiscovery.swift
//  VultisigApp

import SwiftUI
import RiveRuntime

struct KeysignInput: Hashable {
    let vault: Vault
    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let keysignType: KeyType
    let messsageToSign: [String]
    let keysignPayload: KeysignPayload? // need to pass it along to the next view
    let customMessagePayload: CustomMessagePayload?
    let encryptionKeyHex: String
    let isInitiateDevice: Bool
    let fastVaultPassword: String?
}

struct KeysignDiscoveryView: View {
    let vault: Vault
    let keysignPayload: KeysignPayload?
    let customMessagePayload: CustomMessagePayload? // TODO: Switch to enum
    let fastVaultPassword: String?
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel
    @State var previewType: QRShareSheetType = .Send
    var swapTransaction: SwapTransaction = SwapTransaction()
    var contentPadding: CGFloat?
    var onKeysignInput: (KeysignInput) -> Void

    @StateObject var participantDiscovery = ParticipantDiscovery()
    @StateObject var viewModel = KeysignDiscoveryViewModel()

    @State var isLoading = false
    @State var screenWidth: CGFloat = 0
    @State var screenHeight: CGFloat = 0
    @State var qrCodeImage: Image? = nil
    @State var selectedNetwork = VultisigRelay.IsRelayEnabled ? NetworkPromptType.Internet : NetworkPromptType.Local

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

    var localModeAvailable: Bool { vault.libType != .KeyImport }

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
        .onLoad {
            Task { @MainActor in
                qrScannedAnimation = RiveViewModel(fileName: "qrscanner", autoPlay: true)
                await setData()
                viewModel.startDiscovery()
            }
        }
        .onDisappear {
            viewModel.stopDiscovery()
            shareSheetViewModel.clear()
            self.qrCodeImage = nil
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
            switchLink
                .background(Theme.colors.bgPrimary)
                .showIf(localModeAvailable)
        }
    }

    var portraitContent: some View {
        ScrollView(showsIndicators: false) {
            paringQRCode
            disclaimer
            list
        }
        .padding(.horizontal, contentPadding ?? 16)
    }

    @ViewBuilder
    var paringQRCode: some View {
        ZStack {
            qrScannedAnimation?.view()
            qrCode
        }
        .padding(.bottom)
    }

    var disclaimer: some View {
        ZStack {
            if selectedNetwork == .Local {
                LocalModeDisclaimer()
            }
        }
    }

    var listTitle: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("devices", comment: ""))
            Text("(\(viewModel.selections.count)/\(vault.getThreshold()+1))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(Theme.fonts.title2)
        .foregroundColor(Theme.colors.textPrimary)
        .padding(.bottom, 8)
        .padding(.horizontal, 8)
    }

    var lookingForDevices: some View {
        KeygenAnimationView(
            isFast: keysignState == .fast,
            connected: .constant(false),
            progress: .constant(0)
        )
    }

    var keysignState: SetupVaultState {
        return fastVaultPassword == nil ? .secure : .fast
    }

    func setData() async {
        if VultisigRelay.IsRelayEnabled {
            self.selectedNetwork = .Internet
        } else {
            self.selectedNetwork = .Local
        }

        await viewModel.setData(
            vault: vault,
            keysignPayload: keysignPayload,
            customMessagePayload: customMessagePayload,
            participantDiscovery: participantDiscovery,
            fastVaultPassword: fastVaultPassword,
            onFastKeysign: { startKeysign() }
        )

        guard let (qrCodeData, qrCodeImage) = await viewModel.getQrImage() else {
            return
        }

        self.qrCodeImage = qrCodeImage
        shareSheetViewModel.render(
            qrCodeImage: qrCodeImage,
            qrCodeData: qrCodeData,
            displayScale: displayScale,
            type: previewType,
            vaultName: vault.name,
            amount: previewType == .Send ? keysignPayload?.toAmountWithTickerString ?? "" : "",
            toAddress: previewType == .Send ? keysignPayload?.toAddress ?? "" : "",
            fromAmount: previewType == .Swap ? getSwapFromAmount() : "",
            toAmount: previewType == .Swap ? getSwapToAmount() : ""
        )
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
            let keysignInput = viewModel.startKeysign(vault: vault)
            onKeysignInput(keysignInput)
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
    KeysignDiscoveryView(
        vault: Vault.example,
        keysignPayload: KeysignPayload.example,
        customMessagePayload: nil,
        fastVaultPassword: nil,
        shareSheetViewModel: ShareSheetViewModel()
    ) { _ in }
        .environmentObject(SettingsViewModel())
}
