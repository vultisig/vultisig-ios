//
//  ResharePeerDiscoveryView.swift
//  VoltixApp
//
//  Created by Johnny Luo on 14/3/2024.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Mediator
import OSLog
import Security
import SwiftUI

private let logger = Logger(subsystem: "reshare-peers-discory", category: "communication")
struct ResharePeerDiscoveryView: View {
    enum ResharePeerDiscoveryStatus {
        case WaitingForDevices
        case Reshare
        case Failure
    }

    let vault: Vault
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @State private var selections = Set<String>()
    private let mediator = Mediator.shared
    private let serverAddr = "http://127.0.0.1:8080"
    private let sessionID = UUID().uuidString
    @State private var currentState = ResharePeerDiscoveryStatus.WaitingForDevices
    @State private var localPartyID = ""
    @ObservedObject var participantDiscovery = ParticipantDiscovery()
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
                    Text(NSLocalizedString("scanQrCode", comment: "Scan the QR Code above").uppercased())
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
                    self.currentState = .Reshare
                    self.participantDiscovery.stop()
                }) {
                    HStack {
                        Text(NSLocalizedString("reshare", comment: "Reshare"))
                            .font(.title30MenloBold)
                            .fontWeight(.black)
                        Image(systemName: "chevron.right")
                            .resizable()
                            .frame(width: 10, height: 15)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(self.selections.count < 3)
            case .Reshare:
                Text("reshare")
//                KeygenView(presentationStack: self.$presentationStack,
//                           keygenCommittee: self.selections.map { $0 },
//                           mediatorURL: self.serverAddr,
//                           sessionID: self.sessionID,
//                           localPartyKey: self.localPartyID,
//                           hexChainCode: self.chainCode ?? "",
//                           vaultName: self.appState.creatingVault?.name ?? "New Vault")
            case .Failure:
                Text("Something is wrong")
            }
        }
        .navigationTitle(NSLocalizedString("mainDevice", comment: "Main Device"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationButtons.backButton(presentationStack: self.$presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
        }
        .task {
            self.mediator.start(name: self.serviceName)
            logger.info("mediator server started")
            self.startSession()
            self.participantDiscovery.getParticipants(serverAddr: self.serverAddr, sessionID: self.sessionID)
        }.onAppear {
            if !vault.localPartyID.isEmpty {
                self.localPartyID = localPartyID
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
        let km = ReshareMessage(sessionID: sessionID,
                                hexChainCode: vault.hexChainCode,
                                serviceName: self.serviceName,
                                pubKeyECDSA: self.vault.pubKeyECDSA,
                                signers: self.vault.signers)
        let jsonEncoder = JSONEncoder()
        do {
            let data = try jsonEncoder.encode(km)
            return Utils.getQrImage(data: data, size: size)
        } catch {
            logger.error("fail to encode keygen message to json,error:\(error.localizedDescription)")
            return Image(systemName: "xmark")
        }
    }
    
    private func startSession() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
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

struct ReshareMessage: Codable {
    let sessionID: String
    let hexChainCode: String
    let serviceName: String
    let pubKeyECDSA: String // let's use ECDSA pubkey as a way to make sure each participants are using the correct vault
    let signers: [String] // list of old parties
}

#Preview {
    ResharePeerDiscoveryView(vault: Vault.example, presentationStack: .constant([]))
}
