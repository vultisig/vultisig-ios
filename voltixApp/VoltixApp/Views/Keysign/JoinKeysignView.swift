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
    @State private var sessionID: String = ""
    @State private var keysignMessages = [String]()
    @ObservedObject private var serviceDelegate = ServiceDelegate()
    @State private var netService = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    @State private var currentStatus = JoinKeysignStatus.DiscoverSigningMsg
    @State private var keysignCommittee = [String]()
    @State var localPartyID: String = ""
    @State private var errorMsg: String = ""
    @State private var keysignPayload: KeysignPayload? = nil
    @State private var serviceName = ""
    
    var body: some View {
        VStack {
            VStack {
                switch self.currentStatus {
                    case .DiscoverSigningMsg:
                        Text("Please scan the QR code displayed on another VoltixApp device.")
                            .font(Font.custom("Menlo", size: 15)
                                .weight(.bold))
                            .multilineTextAlignment(.center)
                        
                        Button("Scan", systemImage: "qrcode.viewfinder") {
                            self.isShowingScanner = true
                        }
                        .sheet(isPresented: self.$isShowingScanner, content: {
                            CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                        })
                    case .DiscoverService:
                        VStack {
                            HStack {
                                Text("thisDevice")
                                Text(":" + self.localPartyID)
                            }
                            HStack {
                                Text("Looking for the mediator service...")
                                    .font(Font.custom("Menlo", size: 15)
                                        .weight(.bold))
                                    .multilineTextAlignment(.center)
                                if self.serviceDelegate.serverURL == nil {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .padding(2)
                                } else {
                                    Image(systemName: "checkmark").onAppear {
                                        self.currentStatus = .JoinKeysign
                                    }
                                }
                            }
                        }.onAppear {
                            logger.info("Start to discover service")
                            self.netService = NetService(domain: "local.", type: "_http._tcp.", name: self.serviceName)
                            self.netService.delegate = self.serviceDelegate
                            self.netService.resolve(withTimeout: TimeInterval(10))
                        }
                    case .JoinKeysign:
                        VStack(alignment: .leading) {
                            VStack {
                                VStack(alignment: .center) {
                                    Text("Confirm to sign the message?")
                                        .font(Font.custom("Menlo", size: 15)
                                            .weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider()
                            
                            HStack {
                                Text("To: ")
                                    .font(Font.custom("Menlo", size: 15).weight(.bold))
                                
                                Text("\(self.keysignPayload?.toAddress ?? "")")
                                    .font(Font.custom("Menlo", size: 12))
                            }
                            .padding(.vertical)
                            
                            Text("Amount: \(String(self.keysignPayload?.toAmount ?? 0))")
                                .font(Font.custom("Menlo", size: 15).weight(.bold))
                                .padding(.vertical)
                            
                            VStack {
                                VStack(alignment: .center) {
                                    Button(action: {
                                        self.joinKeysignCommittee()
                                        self.currentStatus = .WaitingForKeysignToStart
                                    }) {
                                        Label("Join signing", systemImage: "person.2.badge.key")
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .padding(.vertical, 15)
                        }
                    case .WaitingForKeysignToStart:
                        VStack {
                            HStack {
                                Text("thisDevice")
                                Text(":" + self.localPartyID)
                            }
                            HStack {
                                Text("Waiting for the signing process to begin...")
                                    .font(Font.custom("Menlo", size: 15)
                                        .weight(.bold))
                                    .multilineTextAlignment(.center)
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding(2)
                            }
                        }.task {
                            Task {
                                repeat {
                                    self.checkKeysignStarted()
                                    try await Task.sleep(for: .seconds(1))
                                } while self.currentStatus == .WaitingForKeysignToStart
                            }
                        }
                    case .KeysignStarted:
                        HStack {
                            if self.serviceDelegate.serverURL != nil && !self.sessionID.isEmpty {
                                KeysignView(presentationStack: self.$presentationStack,
                                            keysignCommittee: self.keysignCommittee,
                                            mediatorURL: self.serviceDelegate.serverURL ?? "",
                                            sessionID: self.sessionID,
                                            keysignType: self.keysignPayload?.coin.chain.signingKeyType ?? .ECDSA,
                                            messsageToSign: self.keysignMessages,
                                            localPartyKey: self.localPartyID,
                                            keysignPayload: self.keysignPayload)
                            } else {
                                Text("Unable to start the keysign process due to missing information.")
                                    .font(Font.custom("Menlo", size: 15)
                                        .weight(.bold))
                                    .multilineTextAlignment(.center)
                            }
                        }.navigationBarBackButtonHidden(true)
                    case .FailedToStart:
                        Text("The keysign process could not be started. Please check your settings and try again.")
                            .font(Font.custom("Menlo", size: 15)
                                .weight(.bold))
                            .multilineTextAlignment(.center)
                }
            }
            .padding()
            .background(Color(UIColor.systemFill))
            .cornerRadius(10)
            .shadow(radius: 5)
            .padding()
        }
        .navigationTitle("Join Key Signing")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationButtons.backButton(presentationStack: self.$presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
        }
        .onAppear {
            if self.appState.currentVault == nil {
                self.errorMsg = "Vault is unavailable."
                self.currentStatus = .FailedToStart
            }
            
            if let localPartyID = appState.currentVault?.localPartyID, !localPartyID.isEmpty {
                self.localPartyID = localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
            }
        }
    }
    
    private func checkKeysignStarted() {
        guard let serverUrl = serviceDelegate.serverURL else {
            logger.error("Server URL could not be found. Please ensure you're connected to the correct network.")
            return
        }
        guard !self.sessionID.isEmpty else {
            logger.error("Session ID has not been acquired. Please scan the QR code again.")
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
                            self.keysignCommittee.append(contentsOf: peers)
                            self.currentStatus = .KeysignStarted
                            logger.info("Keysign process has started successfully.")
                        }
                    } catch {
                        logger.error("There was an issue processing the keysign start response. Please try again.")
                    }
                case .failure(let error):
                    let err = error as NSError
                    if err.code == 404 {
                        logger.info("Waiting for keysign to start. Please stand by.")
                    } else {
                        logger.error("Failed to verify keysign start. Error: \(error.localizedDescription)")
                    }
            }
        })
    }
    
    private func joinKeysignCommittee() {
        guard let serverUrl = serviceDelegate.serverURL else {
            logger.error("Server URL could not be found. Please ensure you're connected to the correct network.")
            return
        }
        guard !self.sessionID.isEmpty else {
            logger.error("Session ID has not been acquired. Please scan the QR code again.")
            return
        }
        
        let urlString = "\(serverUrl)/\(sessionID)"
        let body = [self.localPartyID]
        
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                logger.info("Successfully joined the keysign committee.")
            } else {
                logger.error("Failed to join the keysign committee. Please check your connection and try again.")
            }
        }
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
                        self.keysignPayload = keysignMsg.payload
                        self.serviceName = keysignMsg.serviceName
                        logger.info("QR code scanned successfully. Session ID: \(self.sessionID)")
                        self.prepareKeysignMessages(keysignPayload: keysignMsg.payload)
                    } catch {
                        logger.error("Failed to decode keysign message. Error: \(error.localizedDescription)")
                        self.errorMsg = "Error decoding keysign message: \(error.localizedDescription)"
                        self.currentStatus = .FailedToStart
                    }
                }
            case .failure(let err):
                logger.error("Failed to scan QR code. Error: \(err.localizedDescription)")
                self.errorMsg = "QR code scanning failed: \(err.localizedDescription)"
                self.currentStatus = .FailedToStart
        }
        self.currentStatus = .DiscoverService
    }
    
    private func prepareKeysignMessages(keysignPayload: KeysignPayload) {
        let result = keysignPayload.getKeysignMessages()
        switch result {
            case .success(let preSignedImageHash):
                logger.info("Successfully prepared messages for keysigning.")
                self.keysignMessages = preSignedImageHash.sorted()
                if self.keysignMessages.isEmpty {
                    logger.error("There is nothing to be signed")
                    self.currentStatus = .FailedToStart
                }
            case .failure(let err):
                logger.error("Failed to prepare messages for keysigning. Error: \(err)")
                self.currentStatus = .FailedToStart
        }
    }
}

#Preview {
    JoinKeysignView(presentationStack: .constant([]))
}
