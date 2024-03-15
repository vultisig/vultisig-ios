//
//  JoinKeysignView.swift
//  VoltixApp

import CodeScanner
import OSLog
import SwiftUI

struct JoinKeysignView: View {
    let vault: Vault
    private let logger = Logger(subsystem: "join-keysign", category: "communication")
    enum JoinKeysignStatus {
        case DiscoverSigningMsg
        case DiscoverService
        case JoinKeysign
        case WaitingForKeysignToStart
        case KeysignStarted
        case FailedToStart
    }
    
    @State private var isShowingScanner = false
    @State private var sessionID: String = ""
    @State private var keysignMessages = [String]()
    @StateObject private var serviceDelegate = ServiceDelegate()
    @State private var netService: NetService? = nil
    @State private var currentStatus = JoinKeysignStatus.DiscoverSigningMsg
    @State private var keysignCommittee = [String]()
    @State var localPartyID: String = ""
    @State private var errorMsg: String = ""
    @State private var keysignPayload: KeysignPayload? = nil
    @State private var serviceName = ""
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            self.background
            VStack {
                switch self.currentStatus {
                case .DiscoverSigningMsg:
                    self.discoveringSignMessage
                case .DiscoverService:
                    self.discoverService
                case .JoinKeysign:
                    self.keysignMessageConfirm
                case .WaitingForKeysignToStart:
                    self.waitingForKeySignStart
                case .KeysignStarted:
                    HStack {
                        if self.serviceDelegate.serverURL != nil && !self.sessionID.isEmpty {
                            KeysignView(vault:vault,
                                        keysignCommittee: self.keysignCommittee,
                                        mediatorURL: self.serviceDelegate.serverURL ?? "",
                                        sessionID: self.sessionID,
                                        keysignType: self.keysignPayload?.coin.chain.signingKeyType ?? .ECDSA,
                                        messsageToSign: self.keysignMessages,
                                        localPartyKey: self.localPartyID,
                                        keysignPayload: self.keysignPayload)
                        } else {
                            Text("Unable to start the keysign process due to missing information.")
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                        }
                    }.navigationBarBackButtonHidden(true)
                case .FailedToStart:
                    VStack {
                        Text(NSLocalizedString("keysignFail", comment: "Failed to start the keysign process"))
                            .font(.body15MenloBold)
                            .multilineTextAlignment(.center)
                        Text(self.errorMsg).font(.body15MenloBold)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .cornerRadius(10)
            .shadow(radius: 5)
        }
        .navigationTitle(NSLocalizedString("joinKeysign", comment: "Join Keysign"))
        .sheet(isPresented: self.$isShowingScanner, content: {
            CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
        })
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
        }
        .onAppear {
            if !self.vault.localPartyID.isEmpty {
                self.localPartyID = self.vault.localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
            }
        }
        .onDisappear {
            self.currentStatus = .FailedToStart
        }
    }
    
    var keysignMessageConfirm: some View {
        VStack(alignment: .leading) {
            VStack {
                VStack(alignment: .center) {
                    Text("Confirm to sign the message?")
                        .font(.body15MenloBold)
                        .foregroundColor(.neutral0)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            HStack {
                Text("To: ")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                
                Text("\(self.keysignPayload?.toAddress ?? "")")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical)
            
            Text("Amount: \(String(self.keysignPayload?.toAmount ?? 0))")
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
                .padding(.vertical)
            
            VStack {
                VStack(alignment: .center) {
                    Button(action: {
                        self.joinKeysignCommittee()
                        self.currentStatus = .WaitingForKeysignToStart
                    }) {
                        FilledButton(title: "joinKeySign")
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .padding(.vertical, 15)
        }
    }

    var waitingForKeySignStart: some View {
        VStack {
            HStack {
                Text("thisDevice")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                Text(self.localPartyID)
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Text(NSLocalizedString("waitingForKeySignStart", comment: "Waiting for the keysign process to start"))
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
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
    }
    
    var discoveringSignMessage: some View {
        VStack {
            Text(NSLocalizedString("scanQRCodeJoinKeygen", comment: "Scan the barcode on another VoltixApp device to start"))
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
            
            Button(action: {
                self.isShowingScanner = true
            }) {
                self.scanButton
            }
        }
    }
    
    var discoverService: some View {
        VStack {
            HStack {
                Text("thisDevice")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                Text(self.localPartyID)
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Text(NSLocalizedString("discoveringMediator", comment: "Discovering mediator service, please wait..."))
                    .foregroundColor(.neutral0)
                    .font(.body15MenloBold)
                    .multilineTextAlignment(.center)
                
                if self.serviceDelegate.serverURL == nil {
                    ProgressView().progressViewStyle(.circular).padding(2)
                } else {
                    Image(systemName: "checkmark").onAppear {
                        self.currentStatus = .JoinKeysign
                    }
                }
            }
        }.padding(.vertical, 30)
            .onAppear {
                self.logger.info("Start to discover service")
                self.netService = NetService(domain: "local.", type: "_http._tcp.", name: self.serviceName)
                self.netService?.delegate = self.serviceDelegate
                self.netService?.resolve(withTimeout: 10)
            }
    }
    
    var scanButton: some View {
        ZStack {
            Circle()
                .foregroundColor(.blue800)
                .frame(width: 80, height: 80)
                .opacity(0.8)
            
            Circle()
                .foregroundColor(.turquoise600)
                .frame(width: 60, height: 60)
            
            Image(systemName: "camera")
                .font(.title30MenloUltraLight)
                .foregroundColor(.blue600)
        }
    }
    
    private func checkKeysignStarted() {
        guard let serverURL = serviceDelegate.serverURL else {
            self.logger.error("Server URL could not be found. Please ensure you're connected to the correct network.")
            return
        }
        guard !self.sessionID.isEmpty else {
            self.logger.error("Session ID has not been acquired. Please scan the QR code again.")
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
                        self.keysignCommittee.append(contentsOf: peers)
                        self.currentStatus = .KeysignStarted
                        self.logger.info("Keysign process has started successfully.")
                    }
                } catch {
                    self.logger.error("There was an issue processing the keysign start response. Please try again.")
                }
            case .failure(let error):
                let err = error as NSError
                if err.code == 404 {
                    self.logger.info("Waiting for keysign to start. Please stand by.")
                } else {
                    self.logger.error("Failed to verify keysign start. Error: \(error.localizedDescription)")
                }
            }
        })
    }
    
    private func joinKeysignCommittee() {
        guard let serverURL = serviceDelegate.serverURL else {
            self.logger.error("Server URL could not be found. Please ensure you're connected to the correct network.")
            return
        }
        guard !self.sessionID.isEmpty else {
            self.logger.error("Session ID has not been acquired. Please scan the QR code again.")
            return
        }
        
        let urlString = "\(serverURL)/\(sessionID)"
        let body = [self.localPartyID]
        
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                self.logger.info("Successfully joined the keysign committee.")
            } else {
                self.logger.error("Failed to join the keysign committee. Please check your connection and try again.")
            }
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        defer {
            self.isShowingScanner = false
        }
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
                    self.logger.info("QR code scanned successfully. Session ID: \(self.sessionID)")
                    self.prepareKeysignMessages(keysignPayload: keysignMsg.payload)
                } catch {
                    self.logger.error("Failed to decode keysign message. Error: \(error.localizedDescription)")
                    self.errorMsg = "Error decoding keysign message: \(error.localizedDescription)"
                    self.currentStatus = .FailedToStart
                }
            }
        case .failure(let err):
            self.logger.error("Failed to scan QR code. Error: \(err.localizedDescription)")
            self.errorMsg = "QR code scanning failed: \(err.localizedDescription)"
            self.currentStatus = .FailedToStart
        }
        self.currentStatus = .DiscoverService
    }
    
    private func prepareKeysignMessages(keysignPayload: KeysignPayload) {
       
        let result = keysignPayload.getKeysignMessages(vault: vault)
        switch result {
        case .success(let preSignedImageHash):
            self.logger.info("Successfully prepared messages for keysigning.")
            self.keysignMessages = preSignedImageHash.sorted()
            if self.keysignMessages.isEmpty {
                self.logger.error("There is nothing to be signed")
                self.currentStatus = .FailedToStart
            }
        case .failure(let err):
            self.logger.error("Failed to prepare messages for keysigning. Error: \(err)")
            self.currentStatus = .FailedToStart
        }
    }
}

#Preview {
    JoinKeysignView(vault: Vault.example)
}
