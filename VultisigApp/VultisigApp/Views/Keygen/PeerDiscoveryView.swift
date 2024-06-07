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
    
    @StateObject var viewModel = KeygenPeerDiscoveryViewModel()
    @StateObject var participantDiscovery = ParticipantDiscovery(isKeygen: true)
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    
    @State private var orientation = UIDevice.current.orientation
    @State var isLandscape: Bool = false
    
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    @Environment(\.displayScale) var displayScale
    
    let columns = [
        GridItem(.adaptive(minimum: 160)),
        GridItem(.adaptive(minimum: 160)),
        GridItem(.adaptive(minimum: 160)),
    ]
    
    let logger = Logger(subsystem: "peers-discory", category: "communication")
    
    var body: some View {
        ZStack {
            Background()
            states
        }
        .navigationTitle(NSLocalizedString("mainDevice", comment: "Main Device"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .detectOrientation($orientation)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
//            ToolbarItem(placement: .topBarTrailing) {
//                NavigationQRShareButton(title: <#T##String#>, renderedImage: <#T##Image?#>)
//            }
        }
        .task {
            viewModel.startDiscovery()
        }
        .onAppear {
            viewModel.setData(vault: vault, tssType: tssType, participantDiscovery: participantDiscovery)
            setData()
        }
        .onDisappear {
            viewModel.stopMediator()
        }
        .onChange(of: orientation) { oldValue, newValue in
            setData()
        }
    }
    
    var states: some View {
        VStack {
            switch viewModel.status {
            case .WaitingForDevices:
                waitingForDevices
            case .Summary:
                summary
            case .Keygen:
                keygenView
            case .Failure:
                failureText
            }
        }
        .foregroundColor(.neutral0)
    }
    
    var waitingForDevices: some View {
        VStack(spacing: 0) {
            content
            bottomButton
        }
    }
    
    var summary: some View {
        KeyGenSummaryView(viewModel: viewModel)
    }
    
    var content: some View {
        ZStack {
            if isLandscape {
                landscapeContent
            } else {
                portraitContent
            }
        }
    }
    
    var landscapeContent: some View {
        HStack {
            qrCode
            
            VStack{
                list
                    .padding(20)
                vaultDetail
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
        VStack {
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
        HStack {
            Text(NSLocalizedString("lookingForDevices", comment: "Looking for devices"))
                .font(.body15MenloBold)
                .multilineTextAlignment(.center)
            
            ProgressView()
                .preferredColorScheme(.dark)
                .progressViewStyle(.circular)
                .padding(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .cornerRadius(10)
        .shadow(radius: 5)
    }
    
    var paringBarcode: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("pairWithOtherDevices", comment: "Pair with two other devices"))
                .font(.body18MenloBold)
                .multilineTextAlignment(.center)
            
            viewModel.getQrImage(size: 100)
                .resizable()
                .aspectRatio(
                    contentMode:
                        participantDiscovery.peersFound.count == 0 && idiom == .phone ?
                        .fill :
                        .fit
                )
                .padding()
                .frame(maxHeight: .infinity)
                .frame(maxWidth: 512)
                .padding(5)
        }
        .cornerRadius(10)
        .shadow(radius: 5)
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
    
    var scrollList: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                devices
            }
            .padding(.horizontal, 30)
        }
        .padding(idiom == .phone ? 0 : 20)
    }
    
    var gridList: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 32) {
                devices
            }
            .padding(.vertical, 16)
        }
    }
    
    var networkPrompts: some View {
        NetworkPrompts(selectedNetwork: $viewModel.selectedNetwork)
            .padding(.top, idiom == .pad ? 10 : 0)
            .onChange(of: viewModel.selectedNetwork) {
                viewModel.restartParticipantDiscovery()
            }
    }
    
    var devices: some View {
        ForEach(participantDiscovery.peersFound, id: \.self) { peer in
            Button {
                handleSelection(peer)
            } label: {
                PeerCell(id: peer, isSelected: viewModel.selections.contains(peer))
            }
            .onAppear {
                handleAutoSelection()
            }
        }
        .padding(idiom == .phone ? 0 : 8)
    }
    
    var instructions: some View {
        InstructionPrompt(networkType: viewModel.selectedNetwork)
            .padding(.vertical, 10)
    }
    
    var bottomButton: some View {
        Button(action: {
            viewModel.showSummary()
        }) {
            FilledButton(title: "continue")
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .disabled(viewModel.selections.count < 2)
        .opacity(viewModel.selections.count < 2 ? 0.8 : 1)
        .background(Color.backgroundBlue.opacity(0.95))
    }
    
    var keygenView: some View {
        KeygenView(
            vault: viewModel.vault,
            tssType: tssType,
            keygenCommittee: viewModel.selections.map { $0 },
            vaultOldCommittee: viewModel.vault.signers.filter { viewModel.selections.contains($0)
            },
            mediatorURL: viewModel.serverAddr,
            sessionID: viewModel.sessionID,
            encryptionKeyHex: viewModel.encryptionKeyHex ?? "",
            oldResharePrefix: viewModel.vault.resharePrefix ?? "")
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
    
    private func setData() {
        isLandscape = (orientation == .landscapeLeft || orientation == .landscapeRight) && idiom == .pad
        
//        shareSheetViewModel.render(
//            title: addressData,
//            addressData: addressData,
//            displayScale: displayScale
//        )
    }
    
    private func handleSelection(_ peer: String) {
        if viewModel.selections.contains(peer) {
            if peer != viewModel.localPartyID {
                viewModel.selections.remove(peer)
            }
        } else {
            viewModel.selections.insert(peer)
        }
        let totalSigners = viewModel.selections.count
        
        if totalSigners >= 2 {
            let threshold = Int(ceil(Double(totalSigners) * 2.0 / 3.0))
            viewModel.vaultDetail = "\(threshold)of\(totalSigners) Vault"
        }
    }
    
    private func handleAutoSelection() {
        guard tssType == .Keygen else {
            return
        }
        
        if selectedTab == .TwoOfTwoVaults {
            if participantDiscovery.peersFound.count == 1 {
                handleSelection(participantDiscovery.peersFound[0])
                viewModel.showSummary()
            }
        } else if selectedTab == .TwoOfThreeVaults {
            if participantDiscovery.peersFound.count == 1 {
                handleSelection(participantDiscovery.peersFound[0])
            } else if participantDiscovery.peersFound.count == 2 {
                handleSelection(participantDiscovery.peersFound[1])
                viewModel.showSummary()
            }
        }
    }
}

#Preview {
    PeerDiscoveryView(tssType: .Keygen, vault: Vault.example, selectedTab: .TwoOfTwoVaults)
}
