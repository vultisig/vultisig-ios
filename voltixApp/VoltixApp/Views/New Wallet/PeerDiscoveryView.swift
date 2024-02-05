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
            switch currentState {
            case .WaitingForDevices:
                Text("Scan the following QR code to join keygen session")
                Image(uiImage: self.getQrImage(size: 100))
                    .resizable()
                    .scaledToFit()
                    .padding()
                Text("Available devices")
                List(peersFound, id: \.self, selection: $selections) { peer in
                    HStack {
                        Image(systemName: selections.contains(peer) ? "checkmark.circle" : "circle")
                        Text(peer)
                    }
                    .onTapGesture {
                        if selections.contains(peer) {
                            selections.remove(peer)
                        } else {
                            selections.insert(peer)
                        }
                    }
                }
                Button("Create Wallet >") {
                    startKeygen(allParticipants: selections.map { $0 })
                    self.currentState = .Keygen
                    self.discoverying = false
                }
                .disabled(selections.count < 3)
            case .Keygen:
                KeygenView(presentationStack: $presentationStack, keygenCommittee: selections.map { $0 }, mediatorURL: serverAddr, sessionID: self.sessionID, vaultName: appState.creatingVault?.name ?? "New Vault")
            case .Failure:
                Text("Something is wrong")
            }
        }
        .task {
            self.mediator.start()
            logger.info("mediator server started")
            startSession()
            Task {
                repeat {
                    self.getParticipants()
                    try await Task.sleep(nanoseconds: 1_000_000_000) // wait for a second to continue
                } while self.discoverying
            }
        }.onAppear {
            // by this step , creatingVault should be available already
            if appState.creatingVault == nil {
                self.currentState = .Failure
            }
            
            if let localPartyID = appState.creatingVault?.localPartyID, !localPartyID.isEmpty {
                self.localPartyID = localPartyID
            } else {
                self.localPartyID = UIDevice.current.name
                appState.creatingVault?.localPartyID = self.localPartyID
            }
        }
        .onDisappear {
            logger.info("mediator server stopped")
            self.discoverying = false
            self.mediator.stop()
        }
    }
    
    private func getQrImage(size: CGFloat) -> UIImage {
        let context = CIContext()
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else {
            return UIImage(systemName: "xmark") ?? UIImage()
        }
        
        let data = Data(sessionID.utf8)
        qrFilter.setValue(data, forKey: "inputMessage")
        
        guard let qrCodeImage = qrFilter.outputImage else {
            return UIImage(systemName: "xmark") ?? UIImage()
        }
        
        let transformedImage = qrCodeImage.transformed(by: CGAffineTransform(scaleX: size, y: size))
        
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else {
            return UIImage(systemName: "xmark") ?? UIImage()
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func startSession() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        logger.debug("url:\(urlString)")
        
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [self.localPartyID]
        
        do {
            let jsonEncoder = JSONEncoder()
            request.httpBody = try jsonEncoder.encode(body)
        } catch {
            logger.error("Failed to encode body into JSON string: \(error)")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                logger.error("Failed to start session, error: \(error)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                logger.error("Invalid response code")
                return
            }
            
            logger.info("Started session successfully.")
        }
        
        task.resume()
    }

    private func startKeygen(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        logger.debug("url:\(urlString)")
        
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(allParticipants)
            request.httpBody = jsonData
        } catch {
            logger.error("Failed to encode body into JSON string: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                logger.error("Failed to start session, error: \(error)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                logger.error("Invalid response code")
                return
            }
            
            logger.info("Keygen started successfully.")
        }.resume()
    }

    private func getParticipants() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        logger.debug("url:\(urlString)")
        
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                logger.error("Failed to start session, error: \(error)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                logger.error("Invalid response code")
                return
            }
            
            guard let data = data else {
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
        }.resume()
    }
}

#Preview {
    PeerDiscoveryView(presentationStack: .constant([]))
}
