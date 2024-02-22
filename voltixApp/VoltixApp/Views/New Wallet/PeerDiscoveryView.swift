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

func test() {
    let webSocketUrl = "ws://127.0.0.1/websocket"
    let url = URL(string: webSocketUrl)!
    let connection = URLSession.shared.webSocketTask(with: url)

    // connection.receive(completionHandler: )
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
    
    var body: some View {
        VStack {
            switch self.currentState {
            case .WaitingForDevices:
                Text("Scan the following QR code to join keygen session")
                self.getQrImage(size: 100)
                    .resizable()
                    .scaledToFit()
                    .padding()
                Text("CHOOSE TWO PAIR DEVICES:")
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
                Button("Create Wallet >") {
                    self.startKeygen(allParticipants: self.selections.map { $0 })
                    self.currentState = .Keygen
                    self.participantDiscovery.stop()
                }
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("MAIN DEVICE")
        .toolbar {
            ToolbarItem {
                Button("help", systemImage: "questionmark.circle") {
                    // TODO: show help about key gen
                }
            }
        }
        .task {
            self.mediator.start()
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
        let context = CIContext()
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else {
            return Image(systemName: "xmark")
        }
        guard let chainCode = self.chainCode else {
            return Image(systemName: "xmark")
        }
        let km = keygenMessage(sessionID: sessionID, hexChainCode: chainCode)
        let jsonEncoder = JSONEncoder()
        do {
            let data = try jsonEncoder.encode(km)
            qrFilter.setValue(data, forKey: "inputMessage")
        } catch {
            logger.error("fail to encode keygen message to json,error:\(error.localizedDescription)")
            return Image(systemName: "xmark")
        }
        
        guard let qrCodeImage = qrFilter.outputImage else {
            return Image(systemName: "xmark")
        }
        
        let transformedImage = qrCodeImage.transformed(by: CGAffineTransform(scaleX: size, y: size))
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else {
            return Image(systemName: "xmark")
        }
        
        return Image(cgImage, scale: 1.0, orientation: .up, label: Text("QRCode"))
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
}

#Preview {
    PeerDiscoveryView(presentationStack: .constant([]))
}
