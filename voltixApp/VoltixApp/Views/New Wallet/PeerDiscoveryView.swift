//
//  PeerDiscoveryView.swift
//  VoltixApp
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Mediator
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "peers-discory", category: "communication")
struct PeerDiscoveryView: View {
    enum PeerDiscoveryStatus {
        case WaitingForDevices
        case Keygen
        case Failure
    }
    
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @State private var peersFound = [String]()
    @State private var selections = Set<String>()
    private let mediator = Mediator.shared
    // it should be ok to hardcode here , as this view start the mediator server itself
    private let serverAddr = "http://127.0.0.1:8080"
    private let sessionID = UUID().uuidString
    @State private var discoverying = true
    @State private var currentState = PeerDiscoveryStatus.WaitingForDevices
    @State private var localPartyID = ""
    
    var body: some View {
        VStack {
            switch self.currentState {
            case .WaitingForDevices:
                Text("Scan the following QR code to join keygen session")
                self.getQrImage(size: 100)
                    .resizable()
                    .scaledToFit()
                    .padding()
                Text("Available devices")
                List(self.peersFound, id: \.self, selection: self.$selections) { peer in
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
                    self.discoverying = false
                }
                .disabled(self.selections.count < 2) // TODO: Only for testing purpose. 
            case .Keygen:
                KeygenView(presentationStack: self.$presentationStack,
                           keygenCommittee: self.selections.map { $0 },
                           mediatorURL: self.serverAddr,
                           sessionID: self.sessionID,
                           localPartyKey: self.localPartyID,
                           vaultName: self.appState.creatingVault?.name ?? "New Vault")
            case .Failure:
                Text("Something is wrong")
            }
        }
        .navigationBarBackButtonHidden()
        .navigationTitle("Join keygen session")
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
          #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.qrCodeButton(presentationStack: $presentationStack)
            }
          #else
            ToolbarItem {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem {
                NavigationButtons.qrCodeButton(presentationStack: $presentationStack)
            }
          #endif
        }
        .task {
            self.mediator.start()
            logger.info("mediator server started")
            self.startSession()
            Task {
                repeat {
                    self.getParticipants()
                    try await Task.sleep(nanoseconds: 1_000_000_000) // wait for a second to continue
                } while self.discoverying
            }
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
            self.discoverying = false
            self.mediator.stop()
        }
    }
    
    private func getQrImage(size: CGFloat) -> Image {
        let context = CIContext()
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else {
            return Image(systemName: "xmark")
        }
        
        let data = Data(sessionID.utf8)
        qrFilter.setValue(data, forKey: "inputMessage")
        
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
    
    private func getParticipants() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        Utils.getRequest(urlString: urlString, headers: [String: String]()) { result in
            switch result {
            case .success(let data):
                if data.isEmpty {
                    logger.error("No participants available yet")
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    let peers = try decoder.decode([String].self, from: data)
                    
                    for peer in peers {
                        if !self.peersFound.contains(peer) {
                            self.peersFound.append(peer)
                        }
                    }
                } catch {
                    logger.error("Failed to decode response to JSON: \(error)")
                }
            case .failure(let error):
                logger.error("Failed to start session, error: \(error)")
                return
            }
        }
    }
}

#Preview {
    PeerDiscoveryView(presentationStack: .constant([]))
}
