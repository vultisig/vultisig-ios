//
//  PeerDiscoveryView.swift
//  VoltixApp
//

import OSLog
import SwiftUI

struct PeerDiscoveryView: View {
    let tssType: TssType
    let vault: Vault
    
    @StateObject var viewModel = KeygenPeerDiscoveryViewModel()
    @StateObject var participantDiscovery = ParticipantDiscovery()
    
    @State private var orientation = UIDevice.current.orientation
    
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
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
        }
        .task {
            viewModel.startDiscovery()
        }
        .onAppear {
            viewModel.setData(vault: vault, tssType: tssType, participantDiscovery: participantDiscovery)
        }
        .onDisappear {
            viewModel.stopMediator()
        }
    }
    
    var states: some View {
        VStack {
            switch viewModel.status {
            case .WaitingForDevices:
                waitingForDevices
            case .Keygen:
                keygenView
            case .Failure:
                failureText
            }
        }
        .foregroundColor(.neutral0)
    }
    
    var waitingForDevices: some View {
        VStack {
            content
            bottomButtons
        }
    }
    
    var content: some View {
        ZStack {
            if orientation == .landscapeLeft || orientation == .landscapeRight {
                landscapeContent
            } else {
                portraitContent
            }
        }
    }
    
    var landscapeContent: some View {
        HStack {
            paringBarcode
                .padding(60)
            list
                .padding(20)
        }
    }
    
    var portraitContent: some View {
        VStack {
            paringBarcode
            list
        }
    }
    
    var qrCode: some View {
        paringBarcode
    }
    
    var list: some View {
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
        VStack {
            Text(NSLocalizedString("pairWithOtherDevices", comment: "Pair with two other devices"))
                .font(.body18MenloBold)
                .multilineTextAlignment(.center)
            
            viewModel.getQrImage(size: 100)
                .resizable()
                .scaledToFit()
                .padding()
            
            Text(NSLocalizedString("scanQrCode", comment: "Scan QR Code"))
                .font(.body13Menlo)
                .multilineTextAlignment(.center)
        }
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
    }
    
    var deviceList: some View {
        ScrollView{
            ForEach(participantDiscovery.peersFound, id: \.self) { peer in
                VStack(spacing: 12) {
                    Button {
                        handleSelection(peer)
                    } label: {
                        PeerCell(id: peer, isSelected: viewModel.selections.contains(peer))
                    }
                }
            }
            .padding(20)
        }
    }
    
    var bottomButtons: some View {
        Button(action: {
            viewModel.startKeygen()
        }) {
            FilledButton(title: "continue")
                .padding(40)
        }
        .disabled(viewModel.selections.count < 2)
        .opacity(viewModel.selections.count < 2 ? 0.8 : 1)
    }
    
    var keygenView: some View {
        KeygenView(
            vault: vault,
            tssType: tssType,
            keygenCommittee: viewModel.selections.map { $0 },
            vaultOldCommittee: vault.signers.filter { viewModel.selections.contains($0)
            },
            mediatorURL: viewModel.serverAddr,
            sessionID: viewModel.sessionID
        )
    }
    
    var failureText: some View {
        Text(self.viewModel.errorMessage)
            .font(.body15MenloBold)
            .multilineTextAlignment(.center)
            .foregroundColor(.red)
    }
    
    private func handleSelection(_ peer: String) {
        if viewModel.selections.contains(peer) {
            viewModel.selections.remove(peer)
        } else {
            viewModel.selections.insert(peer)
        }
    }
}

#Preview {
    PeerDiscoveryView(tssType: .Keygen, vault: Vault.example)
}
