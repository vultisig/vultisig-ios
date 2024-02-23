    //
    //  JoinKeygen.swift
    //  VoltixApp

import CodeScanner
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "join-committee", category: "communication")

struct JoinKeygenView: View {
    enum JoinKeygenStatus {
        case DiscoverSessionID
        case DiscoverService
        case JoinKeygen
        case WaitingForKeygenToStart
        case KeygenStarted
        case FailToStart
    }
    
    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    @State private var isShowingScanner = false
    @State private var qrCodeResult: String? = nil
    @State private var hexChainCode: String = ""
    @ObservedObject private var serviceDelegate = ServiceDelegate()
    private let netService = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    @State private var currentStatus = JoinKeygenStatus.DiscoverService
    @State private var keygenCommittee = [String]()
    @State var localPartyID: String = ""
    
    var body: some View {
        VStack {
            
            VStack {
                
                
                switch currentStatus {
                    case .DiscoverSessionID:
                        Text("Scan the barcode on another VoltixApp device to start.".uppercased())
                            .font(.custom("Menlo", size: 15).bold())
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            self.isShowingScanner = true
                        }) {
                            HStack{
                                Text("Scan ".uppercased())
                                    .font(.custom("Menlo", size: 15).bold())
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
                        
                        HStack {
                            
                            Text("Discovering mediator service, please wait...".uppercased())
                                .font(.custom("Menlo", size: 15).bold())
                                .multilineTextAlignment(.center)
                            
                            if serviceDelegate.serverUrl == nil {
                                ProgressView().progressViewStyle(.circular).padding(2)
                            } else {
                                Image(systemName: "checkmark").onAppear {
                                    currentStatus = .DiscoverSessionID
                                }
                            }
                            
                        }.padding(.vertical, 30)
                        
                    case .JoinKeygen:
                        
                        HStack {
                            Text("Joining key generation process, please wait...".uppercased())
                                .font(.custom("Menlo", size: 15).bold())
                                .multilineTextAlignment(.center)
                                .onAppear {
                                    joinKeygenCommittee()
                                    currentStatus = .WaitingForKeygenToStart
                                }
                        }.padding(.vertical, 30)
                        
                    case .WaitingForKeygenToStart:
                        HStack {
                            Text("Waiting for key generation to start, please be patient...".uppercased())
                                .font(.custom("Menlo", size: 15).bold())
                                .multilineTextAlignment(.center)
                            ProgressView().progressViewStyle(.circular).padding(2)
                        }
                        .padding(.vertical, 30)
                        .task {
                            Task {
                                repeat {
                                    checkKeygenStarted()
                                    try await Task.sleep(nanoseconds: 1_000_000_000)
                                } while self.currentStatus == .WaitingForKeygenToStart
                            }
                        }
                    case .KeygenStarted:
                        HStack {
                            if serviceDelegate.serverUrl != nil && self.qrCodeResult != nil {
                                KeygenView(presentationStack: $presentationStack,
                                           keygenCommittee: keygenCommittee,
                                           mediatorURL: serviceDelegate.serverUrl!,
                                           sessionID: self.qrCodeResult!,
                                           localPartyKey: self.localPartyID,
                                           hexChainCode: self.hexChainCode,
                                           vaultName: appState.creatingVault?.name ?? "New Vault")
                            } else {
                                Text("Unable to start key generation due to missing information.".uppercased())
                                    .font(.custom("Menlo", size: 15).bold())
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.vertical, 30)
                    case .FailToStart:
                        HStack {
                            Text("Failed to start. Please ensure all prerequisites are met and try again.".uppercased())
                                .font(.custom("Menlo", size: 15).bold())
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 30)
                }
                
            }
            .padding()
            .background(Color(UIColor.systemFill))
            .cornerRadius(10)
            .shadow(radius: 5)
            .padding()
        }
        .navigationTitle("JOIN KEYGEN")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
        }
        .onAppear {
            logger.info("Start to discover service")
            netService.delegate = self.serviceDelegate
            netService.resolve(withTimeout: 10)
            if appState.creatingVault == nil {
                self.currentStatus = .FailToStart
            }
            if let localPartyID = appState.creatingVault?.localPartyID, !localPartyID.isEmpty {
                self.localPartyID = localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
                appState.creatingVault?.localPartyID = self.localPartyID
            }
        }
    }
    
    private func checkKeygenStarted() {
        guard let serverUrl = serviceDelegate.serverUrl, let sessionID = qrCodeResult else {
            logger.error("Required information for checking key generation start is missing.")
            return
        }
        
        let urlString = "\(serverUrl)/start/\(sessionID)"
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
        guard let serverUrl = serviceDelegate.serverUrl, let sessionID = qrCodeResult else {
            logger.error("Required information for joining key generation committee is missing.")
            return
        }
        
        let urlString = "\(serverUrl)/\(sessionID)"
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
                    logger.error("Failed to process scan data.")
                    currentStatus = .FailToStart
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    let keysignMsg = try decoder.decode(keygenMessage.self, from: scanData)
                    qrCodeResult = keysignMsg.sessionID
                    hexChainCode = keysignMsg.hexChainCode
                } catch {
                    logger.error("Failed to decode key generation message: \(error.localizedDescription)")
                    currentStatus = .FailToStart
                    return
                }
                currentStatus = .JoinKeygen
            case .failure(let error):
                logger.error("Failed to scan QR code: \(error.localizedDescription)")
                currentStatus = .FailToStart
                return
        }
    }
}

final class ServiceDelegate: NSObject, NetServiceDelegate, ObservableObject {
    @Published var serverUrl: String?
    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        logger.info("Service found: \(sender.name), \(sender.hostName ?? ""), port \(sender.port) in domain \(sender.domain)")
        serverUrl = "http://\(sender.hostName ?? ""):\(sender.port)"
    }
}

struct JoinKeygenView_Previews: PreviewProvider {
    static var previews: some View {
        JoinKeygenView(presentationStack: .constant([]))
    }
}
