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

func getChainCode() -> String? {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    
    guard status == errSecSuccess else {
        print("Error generating random bytes: \(status)")
        return nil
    }
    
    return bytesToHexString(bytes)
}

func bytesToHexString(_ bytes: [UInt8]) -> String {
    return bytes.map { String(format: "%02x", $0) }.joined()
}

private let logger = Logger(subsystem: "peers-discory", category: "communication")
struct PeerDiscoveryView: View {
    enum PeerDiscoveryStatus {
        case WaitingForDevices
        case Keygen
        case Failure
    }
    
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @State private var selections = Set<String>()
    private let mediator = Mediator.shared
    // it should be ok to hardcode here , as this view start the mediator server itself
    private let serverAddr = "http://127.0.0.1:8080"
    private let sessionID = UUID().uuidString
    private let chainCode = getChainCode()
    @State private var currentState = PeerDiscoveryStatus.WaitingForDevices
    @State private var localPartyID = ""
    @ObservedObject var participantDiscovery = ParticipantDiscovery()
    private let serviceName = "VoltixApp-" + Int.random(in: 1 ... 1000).description
    
    var body: some View {
        VStack {
            switch self.currentState {
                case .WaitingForDevices:
                    
                    VStack {
                        Text("Pair with two other devices:".uppercased())
                            .font(.custom("Menlo", size: 18).bold())
                            .multilineTextAlignment(.center)
                        self.getQrImage(size: 100)
                            .resizable()
                            .scaledToFit()
                            .padding()
                        Text("Scan the above QR CODE.".uppercased())
                            .font(.custom("Menlo", size: 13))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color(UIColor.systemFill))
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding()
                    
                    // TODO: Validate if it is <= 3 devices
                    if self.participantDiscovery.peersFound.count == 0 {
                        VStack {
                            HStack {
                                Text("Looking for devices... ")
                                    .font(Font.custom("Menlo", size: 15)
                                        .weight(.bold))
                                    .multilineTextAlignment(.center)
                                
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding(2)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.systemFill))
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
                            Text("CREATE WALLET".uppercased())
                                .font(Font.custom("Menlo", size: 30).weight(.bold))
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
                               hexChainCode: self.chainCode ?? "",
                               vaultName: self.appState.creatingVault?.name ?? "New Vault")
                case .Failure:
                    Text("Something is wrong")
            }
        }
        .navigationTitle("MAIN DEVICE")
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
            // by this step , creatingVault should be available already
            if self.appState.creatingVault == nil {
                self.currentState = .Failure
                return
            }
            
            if let localPartyID = appState.creatingVault?.localPartyID, !localPartyID.isEmpty {
                self.localPartyID = localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
                self.appState.creatingVault?.localPartyID = self.localPartyID
            }
        }
        .onDisappear {
            logger.info("mediator server stopped")
            self.participantDiscovery.stop()
            self.mediator.stop()
        }
    }
    
    private func getQrImage(size: CGFloat) -> Image {
        guard let chainCode = self.chainCode else {
            return Image(systemName: "xmark")
        }
        let km = keygenMessage(sessionID: sessionID, hexChainCode: chainCode, serviceName: self.serviceName)
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

struct keygenMessage: Codable {
    let sessionID: String
    let hexChainCode: String
    let serviceName: String
}

#Preview {
    PeerDiscoveryView(presentationStack: .constant([]))
}
