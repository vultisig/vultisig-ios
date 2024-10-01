//
//  PeerDiscoveryView.swift
//  VultisigApp
//

import OSLog
import SwiftUI

struct PeerDiscoveryView: View {
    let tssType: TssType
    let vault: Vault
    let selectedTab: SetupVaultState
    let fastVaultEmail: String?
    let fastVaultPassword: String?
    let fastVaultExist: Bool

    @StateObject var viewModel = KeygenPeerDiscoveryViewModel()
    @StateObject var participantDiscovery = ParticipantDiscovery(isKeygen: true)
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    
    @State var qrCodeImage: Image? = nil
    @State var isLandscape: Bool = true
    @State var isPhoneSE = false
    
    @State var screenWidth: CGFloat = .zero
    @State var screenHeight: CGFloat = .zero
    
    @State private var showInvalidNumberOfSelectedDevices = false
    
    @Environment(\.displayScale) var displayScale
    
#if os(iOS)
    @State var orientation = UIDevice.current.orientation
#endif
    
    let columns = [
        GridItem(.adaptive(minimum: 160)),
        GridItem(.adaptive(minimum: 160)),
        GridItem(.adaptive(minimum: 160)),
    ]
    
    let logger = Logger(subsystem: "peers-discory", category: "communication")
    
    var body: some View {
        content
            .task {
                viewModel.startDiscovery()
            }
            .onAppear {
                viewModel.setData(
                    vault: vault,
                    tssType: tssType, 
                    state: selectedTab,
                    participantDiscovery: participantDiscovery,
                    fastVaultPassword: fastVaultPassword, 
                    fastVaultEmail: fastVaultEmail,
                    fastVaultExist: fastVaultExist
                )
                setData()
            }
            .onDisappear {
                viewModel.stopMediator()
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
            case (.Summary, _):
                summary
            case (.Keygen, _):
                keygenView
            case (.Failure, _):
                failureText
            }
        }
        .foregroundColor(.neutral0)
    }

    var waitingForDevices: some View {
        VStack(spacing: 0) {
            views
            bottomButton
        }
    }
    
    var summary: some View {
        KeyGenSummaryView(state: selectedTab, viewModel: viewModel)
    }
    
    var views: some View {
        ZStack {
            if isLandscape {
                landscapeContent
            } else {
                portraitContent
            }
        }
    }
    
    var portraitContent: some View {
        VStack(spacing: 0) {
            vaultDetail
            qrCode
            list
        }
    }
    
    var qrCode: some View {
        paringBarcode
    }
    
    var list: some View {
        VStack(spacing: isPhoneSE ? 4 : 12) {
            networkPrompts
            deviceContent
            instructions
        }
    }
    
    var deviceContent: some View {
        ZStack {
            if participantDiscovery.peersFound.count == 0 {
                lookingForDevices
            } else {
                deviceList
            }
        }
    }
    
    var lookingForDevices: some View {
        LookingForDevicesLoader(selectedTab: selectedTab)
    }
    
    var deviceList: some View {
        ZStack {
            if isLandscape {
                gridList
            } else {
                scrollList
            }
        }
    }
    
    var instructions: some View {
        InstructionPrompt(networkType: viewModel.selectedNetwork)
            .padding(.vertical, isPhoneSE ? 0 : 10)
    }
    
    func disableContinueButton() -> Bool {
        switch selectedTab {
        case .fast:
            return viewModel.selections.count < 2
        case .active:
            return viewModel.selections.count < 3
        case .secure:
            return viewModel.selections.count < 2
        }
    }
    
    var keygenView: some View {
        KeygenView(
            vault: viewModel.vault,
            tssType: tssType,
            keygenCommittee: viewModel.selections.map { $0 },
            vaultOldCommittee: viewModel.vault.signers.filter { viewModel.selections.contains($0)},
            mediatorURL: viewModel.serverAddr,
            sessionID: viewModel.sessionID,
            encryptionKeyHex: viewModel.encryptionKeyHex ?? "",
            oldResharePrefix: viewModel.vault.resharePrefix ?? ""
        )
    }
    
    var failureText: some View {
        VStack{
            Text(self.viewModel.errorMessage)
                .font(.body15MenloBold)
                .multilineTextAlignment(.center)
                .foregroundColor(.red)
        }
    }
    
    var vaultDetail: some View {
        Text(viewModel.vaultDetail)
            .font(.body15MenloBold)
            .multilineTextAlignment(.center)
    }
    
    func getTitle() -> String {
        NSLocalizedString("keygenFor", comment: "") +
        " " +
        selectedTab.title +
        " " +
        NSLocalizedString("vault", comment: "")
    }
    
    func setNumberOfPairedDevices() {
        
        let totalSigners = viewModel.selections.count
        
        switch selectedTab {
        case .fast:
            viewModel.vaultDetail = String(format:  NSLocalizedString("numberOfPairedDevicesTwoOfTwo", comment: ""), totalSigners)
        case .active:
            viewModel.vaultDetail = String(format:  NSLocalizedString("numberOfPairedDevicesTwoOfThree", comment: ""), totalSigners)
        default:
            viewModel.vaultDetail = String(format:  NSLocalizedString("numberOfPairedDevicesMOfN", comment: ""), totalSigners)
        }
    }
    
    func setData(_ proxy: GeometryProxy) {
        let screenWidth = proxy.size.width
        
        if screenWidth<380 {
            isPhoneSE = true
        }
    }
}

#Preview {
    PeerDiscoveryView(tssType: .Keygen, vault: Vault.example, selectedTab: .fast, fastVaultEmail: nil, fastVaultPassword: nil, fastVaultExist: false)
}
