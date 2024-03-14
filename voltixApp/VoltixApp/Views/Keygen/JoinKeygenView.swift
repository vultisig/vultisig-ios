//
//  JoinKeygen.swift
//  VoltixApp

import CodeScanner
import Network
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "join-committee", category: "communication")

struct JoinKeygenView: View {
    let vault: Vault
    
    enum JoinKeygenStatus {
        case DiscoverSessionID
        case DiscoverService
        case JoinKeygen
        case WaitingForKeygenToStart
        case KeygenStarted
        case FailToStart
    }

    @State var tssType: TssType = .Keygen
    @Binding var presentationStack: [CurrentScreen]
    @State private var isShowingScanner = false
    @State private var sessionID: String? = nil
    @State private var hexChainCode: String = ""
    @ObservedObject private var serviceDelegate = ServiceDelegate()
    @State private var netService = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    @State private var currentStatus = JoinKeygenStatus.DiscoverSessionID
    @State private var keygenCommittee = [String]()
    @State var oldCommittee = [String]()
    @State var localPartyID: String = ""
    @State private var serviceName = ""
    @State var errorMessage = ""
    
    var body: some View {
        VStack {
            VStack {
                switch currentStatus {
                case .DiscoverSessionID:
                    Text("Scan the barcode on another VoltixApp device to start.".uppercased())
                        .font(.body15MenloBold)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        self.isShowingScanner = true
                    }) {
                        HStack {
                            Text("Scan ".uppercased())
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                            Image(systemName: "qrcode")
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                    }
                    .sheet(isPresented: $isShowingScanner, content: {
                        CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                    })
                    .buttonStyle(PlainButtonStyle())
                    
                case .DiscoverService:
                    VStack {
                        HStack {
                            Text("thisDevice")
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                            Text(self.localPartyID)
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                        }
                        HStack {
                            Text("Discovering mediator service, please wait...".uppercased())
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                            
                            if serviceDelegate.serverURL == nil {
                                ProgressView().progressViewStyle(.circular).padding(2)
                            } else {
                                Image(systemName: "checkmark").onAppear {
                                    currentStatus = .JoinKeygen
                                }
                            }
                        }
                    }.padding(.vertical, 30)
                        .onAppear {
                            logger.info("Start to discover service")
                            self.netService = NetService(domain: "local.", type: "_http._tcp.", name: self.serviceName)
                            netService.delegate = self.serviceDelegate
                            netService.resolve(withTimeout: 10)
                        }
                    
                case .JoinKeygen:
                    VStack {
                        HStack {
                            Text("thisDevice")
                            Text(self.localPartyID)
                        }
                        HStack {
                            Text("Joining key generation process, please wait...".uppercased())
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                                .onAppear {
                                    joinKeygenCommittee()
                                    currentStatus = .WaitingForKeygenToStart
                                }
                        }
                    }.padding(.vertical, 30)
                    
                case .WaitingForKeygenToStart:
                    VStack {
                        HStack {
                            Text("thisDevice")
                            Text(self.localPartyID)
                        }
                        HStack {
                            Text("Waiting for key generation to start, please be patient...".uppercased())
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                            ProgressView().progressViewStyle(.circular).padding(2)
                        }
                    }
                    .padding(.vertical, 30)
                    .task {
                        Task {
                            repeat {
                                checkKeygenStarted()
                                try await Task.sleep(for: .seconds(1))
                            } while self.currentStatus == .WaitingForKeygenToStart
                        }
                    }
                case .KeygenStarted:
                    HStack {
                        if serviceDelegate.serverURL != nil && self.sessionID != nil {
                            KeygenView(presentationStack: $presentationStack,
                                       keygenCommittee: keygenCommittee,
                                       mediatorURL: serviceDelegate.serverURL!,
                                       sessionID: self.sessionID!,
                                       localPartyKey: self.localPartyID,
                                       hexChainCode: self.hexChainCode,
                                       vaultName: vault.name)
                        } else {
                            Text("Unable to start key generation due to missing information.".uppercased())
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 30)
                case .FailToStart:
                    HStack {
                        Text(errorMessage)
                            .font(.body15MenloBold)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 30)
                }
            }
            .padding()
            .background(Color.systemFill)
            .cornerRadius(10)
            .shadow(radius: 5)
            .padding()
        }
        .navigationTitle("JOIN KEYGEN")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
        }
        .onAppear {
            if !vault.localPartyID.isEmpty {
                self.localPartyID = vault.localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
                vault.localPartyID = self.localPartyID
            }
        }.onDisappear {
            self.currentStatus = .FailToStart
        }
    }
    
    private func checkKeygenStarted() {
        guard let serverURL = serviceDelegate.serverURL, let sessionID = sessionID else {
            logger.error("Required information for checking key generation start is missing.")
            return
        }
        
        let urlString = "\(serverURL)/start/\(sessionID)"
        Utils.getRequest(urlString: urlString, headers: [String: String](), completion: { result in
            switch result {
            case .success(let data):
                do {
                    let decoder = JSONDecoder()
                    let peers = try decoder.decode([String].self, from: data)
                    if peers.contains(self.localPartyID) {
                        self.keygenCommittee.append(contentsOf: peers)
                        self.currentStatus = .KeygenStarted
                    }
                } catch {
                    logger.error("Failed to decode response to JSON: \(data)")
                }
            case .failure(let error):
                logger.error("Failed to check if key generation has started, error: \(error)")
            }
        })
    }
    
    private func joinKeygenCommittee() {
        guard let serverURL = serviceDelegate.serverURL, let sessionID = sessionID else {
            logger.error("Required information for joining key generation committee is missing.")
            return
        }
        
        let urlString = "\(serverURL)/\(sessionID)"
        let body = [localPartyID]
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                logger.info("Successfully joined the key generation committee.")
            }
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            guard let scanData = result.string.data(using: .utf8) else {
                errorMessage = "Failed to process scan data."
                currentStatus = .FailToStart
                return
            }
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(PeerDiscoveryPayload.self, from: scanData)
                switch result {
                case .Keygen(let keysignMsg):
                    tssType = .Keygen
                    sessionID = keysignMsg.sessionID
                    hexChainCode = keysignMsg.hexChainCode
                    vault.hexChainCode = hexChainCode
                    serviceName = keysignMsg.serviceName
                case .Reshare(let reshareMsg):
                    tssType = .Reshare
                    oldCommittee = reshareMsg.oldParties
                    sessionID = reshareMsg.sessionID
                    hexChainCode = reshareMsg.hexChainCode
                    // this means the vault is new , and it join the reshare to become the new committee
                    if vault.pubKeyECDSA.isEmpty {
                        vault.hexChainCode = reshareMsg.hexChainCode
                    } else {
                        if vault.pubKeyECDSA != reshareMsg.pubKeyECDSA {
                            errorMessage = "You choose the wrong vault"
                            logger.error("The vault's public key doesn't match the reshare message's public key")
                            currentStatus = .FailToStart
                            return
                        }
                    }
                }
                
            } catch {
                errorMessage = "Failed to decode peer discovery message: \(error.localizedDescription)"
                currentStatus = .FailToStart
                return
            }
            currentStatus = .DiscoverService
        case .failure(let error):
            errorMessage = "Failed to scan QR code: \(error.localizedDescription)"
            currentStatus = .FailToStart
            return
        }
    }
}

final class ServiceDelegate: NSObject, NetServiceDelegate, ObservableObject {
    @Published var serverURL: String?
    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        logger.info("Service found: \(sender.name), \(sender.hostName ?? ""), port \(sender.port) in domain \(sender.domain)")
        serverURL = "http://\(sender.hostName ?? ""):\(sender.port)"
    }
}

struct JoinKeygenView_Previews: PreviewProvider {
    static var previews: some View {
        JoinKeygenView(vault: Vault.example, presentationStack: .constant([]))
    }
}
