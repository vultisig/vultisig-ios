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
    let fastSignConfig: FastSignConfig?

    @StateObject var viewModel = KeygenPeerDiscoveryViewModel()
    @StateObject var participantDiscovery = ParticipantDiscovery(isKeygen: true)
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    
    @State var qrCodeImage: Image? = nil
    @State var isLandscape: Bool = true
    @State var isPhoneSE = false
    
    @State var screenWidth: CGFloat = .zero
    @State var screenHeight: CGFloat = .zero
    
    @State var hideBackButton: Bool = false
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
                    fastSignConfig: fastSignConfig
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
        KeyGenSummaryView(
            state: selectedTab,
            tssType: tssType,
            viewModel: viewModel
        )
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
            if selectedTab == .secure {
                networkPrompts
            }
            
            qrCode
            list
        }
    }
    
    var qrCode: some View {
        paringBarcode
    }
    
    var list: some View {
        VStack(spacing: isPhoneSE ? 4 : 12) {
            deviceContent
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
        LookingForDevicesLoader(
            tssType: tssType,
            selectedTab: selectedTab
        )
    }
    
    var deviceList: some View {
        ZStack {
            if isLandscape {
                gridList
            } else {
                scrollList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            oldResharePrefix: viewModel.vault.resharePrefix ?? "", 
            fastSignConfig: fastSignConfig,
            hideBackButton: $hideBackButton,
            selectedTab: selectedTab
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
    
    var listTitle: some View {
        Text(NSLocalizedString("selectPairingDevices", comment: ""))
            .font(.body14MontserratSemiBold)
            .foregroundColor(.neutral0)
            .padding(.bottom, 8)
    }
    
    func getTitle() -> String {
        guard tssType == .Keygen else {
            return NSLocalizedString("resharingTheVault", comment: "")
        }
        
        return NSLocalizedString("keygenFor", comment: "") +
        " " +
        selectedTab.title +
        " " +
        NSLocalizedString("vault", comment: "")
    }
    
    func setData(_ proxy: GeometryProxy) {
        let screenWidth = proxy.size.width
        
        if screenWidth<380 {
            isPhoneSE = true
        }
    }
}

#Preview {
    PeerDiscoveryView(tssType: .Keygen, vault: Vault.example, selectedTab: .fast, fastSignConfig: nil)
}
