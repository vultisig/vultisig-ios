//
//  PeerDiscoveryView.swift
//  VultisigApp
//

import SwiftUI
import RiveRuntime

struct PeerDiscoveryView: View {
    let tssType: TssType
    let vault: Vault
    let selectedTab: SetupVaultState
    let fastSignConfig: FastSignConfig?
    let keyImportInput: KeyImportInput?
    let setupType: KeyImportSetupType?

    init(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        fastSignConfig: FastSignConfig?,
        keyImportInput: KeyImportInput? = nil,
        setupType: KeyImportSetupType? = nil
    ) {
        self.tssType = tssType
        self.vault = vault
        self.selectedTab = selectedTab
        self.fastSignConfig = fastSignConfig
        self.keyImportInput = keyImportInput
        self.setupType = setupType
    }

    @StateObject var viewModel = KeygenPeerDiscoveryViewModel()
    @StateObject var participantDiscovery = ParticipantDiscovery()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    @State var qrCodeImage: Image? = nil

    @State var showInfoSheet: Bool = false
    @State var hideBackButton: Bool = false

    @State var screenWidth: CGFloat = .zero
    @State var screenHeight: CGFloat = .zero

    @Environment(\.displayScale) var displayScale

#if os(iOS)
    @State var orientation = UIDevice.current.orientation
#endif

    @State var animationVM: RiveViewModel? = nil

    let adaptiveColumns = [
        GridItem(.adaptive(minimum: 350, maximum: 500), spacing: 12),
        GridItem(.adaptive(minimum: 350, maximum: 500), spacing: 12)
    ]

    let adaptiveColumnsMac = [
        GridItem(.adaptive(minimum: 400, maximum: 800), spacing: 12)
    ]

    var localModeAvailable: Bool { tssType != .KeyImport }

    var body: some View {
        content
            .onLoad {
                animationVM = RiveViewModel(fileName: "QRCodeScanned", autoPlay: true)
                viewModel.setData(
                    vault: vault,
                    tssType: tssType,
                    state: selectedTab,
                    participantDiscovery: participantDiscovery,
                    fastSignConfig: fastSignConfig,
                    chains: keyImportInput?.chains
                )
                setData()
                viewModel.startDiscovery()
                if selectedTab == .fast {
                    hideBackButton = true
                }
            }
            .onDisappear {
                viewModel.stopMediator()
                animationVM?.stop()
            }
            .onLoad {
                showInfo()
            }
            .crossPlatformSheet(isPresented: $showInfoSheet) {
                PeerDiscoveryInfoBanner(isPresented: $showInfoSheet)
                    .presentationDetents([.height(450)])
            }
            .onChange(of: viewModel.selectedNetwork) {
                viewModel.restartParticipantDiscovery()
                setData()
            }
    }

    var states: some View {
        VStack {
            switch (viewModel.status, selectedTab.hasOtherDevices) {
            case (.WaitingForDevices, false):
                if viewModel.isLookingForDevices {
                    /// Wait until server join to go to keygen view
                    lookingForDevices
                } else {
                    /// Direct to Keygen for FastVaults
                    keygenView
                }
            case (.WaitingForDevices, true):
                waitingForDevices
            case (.Keygen, _):
                keygenView
            case (.Failure, _):
                failureText
            }
        }
        .foregroundColor(Theme.colors.textPrimary)
        .blur(radius: showInfoSheet ? 1 : 0)
        .animation(.easeInOut, value: showInfoSheet)
    }

    var waitingForDevices: some View {
        VStack(spacing: 0) {
            views
            bottomButton
            switchLink
                .showIf(localModeAvailable)
        }
    }

    var views: some View {
        portraitContent
    }

    var qrCode: some View {
        VStack(spacing: 16) {
            paringBarcode
        }
    }

    var list: some View {
        scrollList
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var lookingForDevices: some View {
        LookingForDevicesLoader(
            tssType: tssType,
            selectedTab: selectedTab
        )
    }

    func disableContinueButton() -> Bool {
        switch viewModel.tssType {
        case .Keygen:
            switch selectedTab {
            case .fast:
                return viewModel.selections.count < 2
            case .active:
                return viewModel.selections.count < 3
            case .secure:
                return viewModel.selections.count < 2
            }
        case .Reshare:
            let requiredCount = vault.getThreshold() + 1
            return viewModel.selections.count < requiredCount
        case .Migrate:
            return Set(viewModel.selections) != Set(viewModel.vault.signers)
        case .KeyImport:
            return showWaitingOnDevice
        }
    }
    
    var showWaitingOnDevice: Bool {
        // Key import requires setupType, and this screen shouldn't be shown for fast
        guard
            let setupType,
            case let .secure(numberOfDevices) = setupType
        else {
            return false
        }
        
        switch numberOfDevices {
        case 0...3:
            return viewModel.selections.count != numberOfDevices
        default:
            return viewModel.selections.count < numberOfDevices
        }
    }

    var keygenView: some View {
        KeygenView(
            vault: viewModel.vault,
            tssType: tssType,
            keygenCommittee: viewModel.keygenCommittee,
            vaultOldCommittee: viewModel.vault.signers.filter { viewModel.selections.contains($0)},
            mediatorURL: viewModel.serverAddr,
            sessionID: viewModel.sessionID,
            encryptionKeyHex: viewModel.encryptionKeyHex ?? "",
            oldResharePrefix: viewModel.vault.resharePrefix ?? "",
            fastSignConfig: fastSignConfig,
            keyImportInput: keyImportInput,
            isInitiateDevice: true,
            hideBackButton: $hideBackButton
        )
    }

    var failureText: some View {
        VStack {
            Text(self.viewModel.errorMessage)
                .font(Theme.fonts.bodyMMedium)
                .multilineTextAlignment(.center)
                .foregroundColor(.red)
        }
    }

    var listTitle: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("devices", comment: ""))

            if tssType == .Migrate {
                Text("(\(viewModel.selections.count)/\(vault.signers.count))")
            } else {
                Text("(\(viewModel.selections.count) \(NSLocalizedString("Selected", comment: "")))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(Theme.fonts.title2)
        .foregroundColor(Theme.colors.textPrimary)
        .animation(.easeInOut, value: viewModel.selections)
    }

    private func showInfo() {
        guard selectedTab == .secure else {
            showInfoSheet = false
            return
        }

        switch self.tssType {
        case .Keygen:
            showInfoSheet = true
        case .Reshare:
            showInfoSheet = false
        case .Migrate:
            showInfoSheet = false
        case .KeyImport:
            showInfoSheet = false
        }
    }
    func getHeaderTitle() -> String {
        if viewModel.status == .WaitingForDevices {
            if selectedTab == .fast {
                return ""
            }
            return tssType == .Migrate ? "" : "scanQR"
        } else if tssType == .Migrate {
            return ""
        } else {
            return ""
        }
    }
}

#Preview {
    PeerDiscoveryView(tssType: .Keygen, vault: Vault.example, selectedTab: .fast, fastSignConfig: nil)
}
