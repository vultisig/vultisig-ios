//
//  PeerDiscoveryView.swift
//  VoltixApp
//

import Mediator
import OSLog
import SwiftUI

struct PeerDiscoveryView: View {
    private let logger = Logger(subsystem: "peers-discory", category: "communication")
    let tssType: TssType
    let vault: Vault
    enum PeerDiscoveryStatus {
        case WaitingForDevices
        case Keygen
        case Failure
    }
    
    @State private var selections = Set<String>()
    private let mediator = Mediator.shared
    // it should be ok to hardcode here , as this view start the mediator server itself
    private let serverAddr = "http://127.0.0.1:8080"
    @State var sessionID = ""
    @State private var currentState = PeerDiscoveryStatus.WaitingForDevices
    @State private var localPartyID = ""
    @StateObject var participantDiscovery = ParticipantDiscovery()
    @State var serviceName = ""
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            self.background
            VStack {
                switch self.currentState {
                case .WaitingForDevices:
                    self.waitingForDevices
                case .Keygen:
                    KeygenView(vault: self.vault,
                               tssType: self.tssType,
                               keygenCommittee: self.selections.map { $0 },
                               vaultOldCommittee: self.vault.signers.filter { selections.contains($0) },
                               mediatorURL: self.serverAddr,
                               sessionID: self.sessionID)
                case .Failure:
                    Text(self.errorMessage)
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
                self.mediator.start(name: self.serviceName)
                self.logger.info("mediator server started")
                self.startSession()
                self.participantDiscovery.getParticipants(serverAddr: self.serverAddr, sessionID: self.sessionID)
            }.onAppear {
                if self.sessionID.isEmpty {
                    self.sessionID = UUID().uuidString
                }
                if self.serviceName.isEmpty {
                    self.serviceName = "VoltixApp-" + Int.random(in: 1 ... 1000).description
                }
                if self.vault.hexChainCode.isEmpty {
                    guard let chainCode = Utils.getChainCode() else {
                        self.logger.error("fail to get chain code")
                        self.currentState = .Failure
                        return
                    }
                    self.vault.hexChainCode = chainCode
                }
                if !self.vault.localPartyID.isEmpty {
                    self.localPartyID = vault.localPartyID
                } else {
                    self.localPartyID = Utils.getLocalDeviceIdentity()
                    self.vault.localPartyID = self.localPartyID
                }
            }
            .onDisappear {
                self.logger.info("mediator server stopped")
                self.participantDiscovery.stop()
                self.mediator.stop()
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
        List(self.participantDiscovery.peersFound, id: \.self, selection: self.$selections) { peer in
            HStack {
                Image(systemName: self.selections.contains(peer) ? "checkmark.circle" : "circle")
                Text(peer)
            }
            .onTapGesture {
                if self.selections.contains(peer) {
                    self.selections.remove(peer)
                } else {
                    self.selections.insert(peer)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    var bottomButtons: some View {
        Button(action: {
            self.startKeygen(allParticipants: self.selections.map { $0 })
            self.currentState = .Keygen
            self.participantDiscovery.stop()
        }) {
            FilledButton(title: "continue")
                .disabled(self.selections.count < 2)
            
        }.disabled(self.selections.count < 2)
            .grayscale(self.selections.count < 2 ? 0 : 1)
    }
    
    private func getQrImage(size: CGFloat) -> Image {
        do {
            let jsonEncoder = JSONEncoder()
            var data: Data
            switch self.tssType {
            case .Keygen:
                let km = keygenMessage(sessionID: sessionID, hexChainCode: vault.hexChainCode, serviceName: self.serviceName)
                data = try jsonEncoder.encode(PeerDiscoveryPayload.Keygen(km))
            case .Reshare:
                let reshareMsg = ReshareMessage(sessionID: sessionID, hexChainCode: vault.hexChainCode, serviceName: self.serviceName, pubKeyECDSA: self.vault.pubKeyECDSA, oldParties: self.vault.signers)
                data = try jsonEncoder.encode(PeerDiscoveryPayload.Reshare(reshareMsg))
            }
            return Utils.getQrImage(data: data, size: size)
        } catch {
            self.logger.error("fail to encode keygen message to json,error:\(error.localizedDescription)")
            return Image(systemName: "xmark")
        }
    }
    
    private func startSession() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        let body = [self.localPartyID]
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                self.logger.info("Started session successfully.")
            } else {
                self.logger.info("Failed to start session.")
            }
        }
    }
    
    private func startKeygen(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        Utils.sendRequest(urlString: urlString, method: "POST", body: allParticipants) { _ in
            self.logger.info("kicked off keygen successfully")
        }
    }
}

#Preview {
    PeerDiscoveryView(tssType: .Keygen, vault: Vault.example)
}
