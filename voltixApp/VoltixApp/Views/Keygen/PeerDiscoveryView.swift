//
//  PeerDiscoveryView.swift
//  VoltixApp
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Mediator
import OSLog
import Security
import SwiftUI

private let logger = Logger(subsystem: "peers-discory", category: "communication")
struct PeerDiscoveryView: View {
    let tssType: TssType
    let vault: Vault
    enum PeerDiscoveryStatus {
        case WaitingForDevices
        case Keygen
        case Failure
    }
    
    @Binding var presentationStack: [CurrentScreen]
    @State private var selections = Set<String>()
    private let mediator = Mediator.shared
    // it should be ok to hardcode here , as this view start the mediator server itself
    private let serverAddr = "http://127.0.0.1:8080"
    private let sessionID = UUID().uuidString
    @State private var currentState = PeerDiscoveryStatus.WaitingForDevices
    @State private var localPartyID = ""
    @StateObject var participantDiscovery = ParticipantDiscovery()
    private let serviceName = "VoltixApp-" + Int.random(in: 1 ... 1000).description
    
    var body: some View {
        VStack {
            switch self.currentState {
                case .WaitingForDevices:
                    
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
                    .padding()
                    .background(Color.systemFill)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding()
                    
                    // TODO: Validate if it is <= 3 devices
                    if self.participantDiscovery.peersFound.count == 0 {
                        VStack {
                            HStack {
                                Text("Looking for devices... ")
                                    .font(.body15MenloBold)
                                    .multilineTextAlignment(.center)
                                
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding(2)
                            }
                        }
                        .padding()
                        .background(Color.systemFill)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        .padding()
                    }
                    
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
                    
                    Button(action: {
                        self.startKeygen(allParticipants: self.selections.map { $0 })
                        self.currentState = .Keygen
                        self.participantDiscovery.stop()
                    }) {
                        HStack {
                            Text(NSLocalizedString("continue", comment: "Continue"))
                                .font(.title30MenloBold)
                                .fontWeight(.black)
                            Image(systemName: "chevron.right")
                                .resizable()
                                .frame(width: 10, height: 15)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    // TODO: Only for testing purpose.
                    .disabled(self.selections.count < 2)
                case .Keygen:
                    KeygenView(presentationStack: self.$presentationStack,
                               keygenCommittee: self.selections.map { $0 },
                               mediatorURL: self.serverAddr,
                               sessionID: self.sessionID,
                               localPartyKey: self.localPartyID,
                               hexChainCode: vault.hexChainCode,
                               vaultName: self.vault.name)
                case .Failure:
                    Text("Something is wrong")
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
            logger.info("mediator server started")
            self.startSession()
            self.participantDiscovery.getParticipants(serverAddr: self.serverAddr, sessionID: self.sessionID)
        }.onAppear {
            if vault.hexChainCode.isEmpty {
                guard let chainCode = Utils.getChainCode() else {
                    logger.error("fail to get chain code")
                    self.currentState = .Failure
                    return
                }
                vault.hexChainCode = chainCode
            }
            if !self.vault.localPartyID.isEmpty {
                self.localPartyID = self.localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
                self.vault.localPartyID = self.localPartyID
            }
        }
        .onDisappear {
            logger.info("mediator server stopped")
            self.participantDiscovery.stop()
            self.mediator.stop()
        }
    }
    
    private func getQrImage(size: CGFloat) -> Image {
        do{
            let jsonEncoder = JSONEncoder()
            var data: Data
            switch tssType {
            case .Keygen:
                let km = keygenMessage(sessionID: sessionID, hexChainCode: vault.hexChainCode, serviceName: self.serviceName)
                data = try jsonEncoder.encode(PeerDiscoveryPayload.Keygen(km))
            case .Reshare:
                let reshareMsg = ReshareMessage(sessionID: sessionID, hexChainCode: vault.hexChainCode, serviceName: self.serviceName, pubKeyECDSA: vault.pubKeyECDSA, oldParties: vault.signers)
                data = try jsonEncoder.encode(PeerDiscoveryPayload.Reshare(reshareMsg))
            default:
                logger.error("invalid tss type")
                self.currentState = .Failure
                return Image(systemName: "xmark")
            }
            return Utils.getQrImage(data: data, size: size)
        }catch {
            logger.error("fail to encode keygen message to json,error:\(error.localizedDescription)")
            return Image(systemName: "xmark")
        }
    }
    
    private func startSession() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        logger.info("start session:\(urlString)")
        let body = [self.localPartyID]
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                logger.info("Started session successfully.")
            } else {
                logger.info("Failed to start session.")
            }
        }
    }
    
    private func startKeygen(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        Utils.sendRequest(urlString: urlString, method: "POST", body: allParticipants) { _ in
            logger.info("kicked off keygen successfully")
        }
    }
}

#Preview {
    PeerDiscoveryView(tssType: .Keygen, vault: Vault.example, presentationStack: .constant([]))
}
