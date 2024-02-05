//
//  JoinKeysignView.swift
//  VoltixApp

import CodeScanner
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "join-keysign", category: "communication")
struct JoinKeysignView: View {
    enum JoinKeysignStatus {
        case DiscoverSigningMsg
        case DiscoverService
        case JoinKeysign
        case WaitingForKeysignToStart
        case KeysignStarted
        case FailedToStart
    }

    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    @State private var isShowingScanner = false
    @State private var sessionID: String? = nil
    @State private var keysignMessage: String? = nil
    @ObservedObject private var serviceDelegate = ServiceDelegate()
    private let netService = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    @State private var currentStatus = JoinKeysignStatus.DiscoverService
    @State private var keysignCommittee = [String]()
    @State var localPartyID: String = ""
    @State private var errorMsg: String = ""
    
    var body: some View {
        VStack {
            switch self.currentStatus {
            case .DiscoverSigningMsg:
                Text("Scan the barcode on another VoltixApp")
                Button("Scan", systemImage: "qrcode.viewfinder") {
                    self.isShowingScanner = true
                }
                .sheet(isPresented: self.$isShowingScanner, content: {
                    CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                })
            case .DiscoverService:
                HStack {
                    Text("discovering mediator service")
                    if self.serviceDelegate.serverUrl == nil {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.blue)
                            .padding(2)
                    } else {
                        Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/ .blue/*@END_MENU_TOKEN@*/).onAppear {
                            self.currentStatus = .DiscoverSigningMsg
                        }
                    }
                }
            case .JoinKeysign:
                Text("Are you sure to sign the following message?")
                Text("keysign message: \(self.keysignMessage ?? "")")
                Button("Join keysign committee", systemImage: "person.2.badge.key") {
                    self.joinKeysignCommittee()
                    self.currentStatus = .WaitingForKeysignToStart
                }
            case .WaitingForKeysignToStart:
                HStack {
                    Text("Waiting for keysign to start")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }.task {
                    Task {
                        repeat {
                            self.checkKeysignStarted()
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        } while self.currentStatus == .WaitingForKeysignToStart
                    }
                }
            case .KeysignStarted:
                HStack {
                    if self.serviceDelegate.serverUrl != nil && self.sessionID != nil {
                        KeysignView(presentationStack: self.$presentationStack,
                                    keysignCommittee: self.keysignCommittee,
                                    mediatorURL: self.serviceDelegate.serverUrl ?? "",
                                    sessionID: self.sessionID ?? "",
                                    keysignType: .ECDSA,
                                    messsageToSign: self.keysignMessage ?? "",
                                    localPartyKey: self.localPartyID)
                    } else {
                        Text("Mediator server url is empty or session id is empty")
                    }
                }.navigationBarBackButtonHidden(true)
            case .FailedToStart:
                // TODO: update this message to be more friendly, it shouldn't happen
                Text("keysign fail to start")
            }
            
        }.onAppear {
            logger.info("start to discover service")
            self.netService.delegate = self.serviceDelegate
            self.netService.resolve(withTimeout: TimeInterval(10))
            // by this step , creatingVault should be available already
            if self.appState.currentVault == nil {
                self.errorMsg = "no vault"
                self.currentStatus = .FailedToStart
            }
            
            if let localPartyID = appState.currentVault?.localPartyID, !localPartyID.isEmpty {
                self.localPartyID = localPartyID
            } else {
                self.localPartyID = UIDevice.current.name
            }
        }
    }

    private func checkKeysignStarted() {
        guard let serverUrl = serviceDelegate.serverUrl else {
            logger.error("didn't discover server url")
            return
        }
        guard let sessionID = self.sessionID else {
            logger.error("session id has not acquired")
            return
        }
        
        let urlString = "\(serverUrl)/start/\(sessionID)"
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                logger.error("Failed to start session, error: \(error)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response")
                return
            }
            
            switch httpResponse.statusCode {
            case 200 ..< 300:
                guard let data = data else {
                    logger.error("No participants available yet")
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    let peers = try decoder.decode([String].self, from: data)
                    let deviceName = UIDevice.current.name
                    
                    if peers.contains(deviceName) {
                        self.keysignCommittee.append(contentsOf: peers)
                        self.currentStatus = .KeysignStarted
                    }
                } catch {
                    logger.error("Failed to decode response to JSON, \(data)")
                }
                
            case 404:
                logger.error("Keygen didn't start yet")
                
            default:
                logger.error("Invalid response code: \(httpResponse.statusCode)")
            }
        }.resume()
    }

    private func joinKeysignCommittee() {
        let deviceName = UIDevice.current.name
        guard let serverUrl = serviceDelegate.serverUrl else {
            logger.error("didn't discover server url")
            return
        }
        guard let sessionID = self.sessionID else {
            logger.error("session id has not acquired")
            return
        }
        
        let urlString = "\(serverUrl)/\(sessionID)"
        logger.debug("url:\(urlString)")
        
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [deviceName]
        
        do {
            let jsonEncoder = JSONEncoder()
            req.httpBody = try jsonEncoder.encode(body)
        } catch {
            logger.error("Failed to encode body into JSON string: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error {
                logger.error("Failed to join session, error: \(error)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                logger.error("Invalid response code")
                return
            }
            
            logger.info("Joined session successfully.")
        }.resume()
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            let decoder = JSONDecoder()
            if let data = qrCodeResult.data(using: .utf8) {
                do {
                    let keysignMsg = try decoder.decode(KeysignMessage.self, from: data)
                    self.sessionID = keysignMsg.sessionID
                    self.keysignMessage = keysignMsg.keysignMessage
                } catch {
                    logger.error("fail to decode keysign message,error:\(error.localizedDescription)")
                    self.errorMsg = error.localizedDescription
                    self.currentStatus = .FailedToStart
                }
            }
            logger.debug("session id: \(result.string)")
        case .failure(let err):
            logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
        self.currentStatus = .JoinKeysign
    }
}

#Preview {
    JoinKeysignView(presentationStack: .constant([]))
}
