//
//  PeerDiscoveryView.swift
//  VoltixApp
//

import OSLog
import SwiftUI

struct PeerDiscoveryView: View {
    private let logger = Logger(subsystem: "peers-discory", category: "communication")
    let tssType: TssType
    let vault: Vault
    @StateObject var viewModel = KeygenPeerDiscoveryViewModel()
    @StateObject var participantDiscovery = ParticipantDiscovery()
    
    var body: some View {
        ZStack {
            self.background
            VStack {
                switch self.viewModel.status {
                case .WaitingForDevices:
                    self.waitingForDevices
                case .Keygen:
                    KeygenView(vault: self.vault,
                               tssType: self.tssType,
                               keygenCommittee: self.viewModel.selections.map { $0 },
                               vaultOldCommittee: self.vault.signers.filter { self.viewModel.selections.contains($0) },
                               mediatorURL: self.viewModel.serverAddr,
                               sessionID: self.viewModel.sessionID)
                case .Failure:
                    Text(self.viewModel.errorMessage)
                        .font(.body15MenloBold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle(NSLocalizedString("mainDevice", comment: "Main Device"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
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
            }.onAppear {
                self.viewModel.setData(vault: vault, tssType: self.tssType, participantDiscovery: self.participantDiscovery)
            }
            .onDisappear {
                viewModel.stopMediator()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var waitingForDevices: some View {
        VStack {
            self.paringBarcode
            if self.participantDiscovery.peersFound.count == 0 {
                self.lookingForDevices
            }
            self.deviceList
            self.bottomButtons
        }
    }
    
    var lookingForDevices: some View {
        VStack {
            HStack {
                Text(NSLocalizedString("lookingForDevices", comment: "Looking for devices"))
                    .font(.body15MenloBold)
                    .multilineTextAlignment(.center)
                
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(2)
            }
        }
        .padding()
        .cornerRadius(10)
        .shadow(radius: 5)
    }
    
    var paringBarcode: some View {
        VStack {
            Text(NSLocalizedString("pairWithOtherDevices", comment: "Pair with two other devices"))
                .font(.body18MenloBold)
                .multilineTextAlignment(.center)
            self.getQrImage(size: 100)
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
        List(participantDiscovery.peersFound, id: \.self, selection: $viewModel.selections) { peer in
            HStack {
                Image(systemName: self.viewModel.selections.contains(peer) ? "checkmark.circle" : "circle")
                Text(peer)
            }
            .onTapGesture {
                if self.viewModel.selections.contains(peer) {
                    self.viewModel.selections.remove(peer)
                } else {
                    self.viewModel.selections.insert(peer)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    var bottomButtons: some View {
        Button(action: {
            viewModel.startKeygen()
        }) {
            FilledButton(title: "continue")
                .padding(40)
        }
        .disabled(self.selections.count < 2)
        .opacity(self.selections.count < 2 ? 0.8 : 1)
    }
    
    private func getQrImage(size: CGFloat) -> Image {
        do {
            let jsonEncoder = JSONEncoder()
            var data: Data
            switch tssType {
            case .Keygen:
                let km = keygenMessage(sessionID: viewModel.sessionID, hexChainCode: viewModel.vault.hexChainCode, serviceName: viewModel.serviceName)
                data = try jsonEncoder.encode(PeerDiscoveryPayload.Keygen(km))
            case .Reshare:
                let reshareMsg = ReshareMessage(sessionID: viewModel.sessionID, hexChainCode: viewModel.vault.hexChainCode, serviceName: viewModel.serviceName, pubKeyECDSA: viewModel.vault.pubKeyECDSA, oldParties: viewModel.vault.signers)
                data = try jsonEncoder.encode(PeerDiscoveryPayload.Reshare(reshareMsg))
            }
            return Utils.getQrImage(data: data, size: size)
        } catch {
            logger.error("fail to encode keygen message to json,error:\(error.localizedDescription)")
            return Image(systemName: "xmark")
        }
    }
}

#Preview {
    PeerDiscoveryView(tssType: .Keygen, vault: Vault.example)
}
