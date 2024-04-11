//
//  JoinKeysignViewModel.swift
//  VoltixApp
//

import Foundation
import OSLog
import CodeScanner

enum JoinKeysignStatus {
    case DiscoverSigningMsg
    case DiscoverService
    case JoinKeysign
    case WaitingForKeysignToStart
    case KeysignStarted
    case FailedToStart
}
@MainActor
class JoinKeysignViewModel: ObservableObject {
    private let logger = Logger(subsystem: "join-keysign", category: "viewmodel")
    var vault: Vault
    var serviceDelegate: ServiceDelegate?
    
    @Published var isShowingScanner = false
    @Published var sessionID: String = ""
    @Published var keysignMessages = [String]()
    @Published var netService: NetService? = nil
    @Published var status = JoinKeysignStatus.DiscoverSigningMsg
    @Published var keysignCommittee = [String]()
    @Published var localPartyID: String = ""
    @Published var errorMsg: String = ""
    @Published var keysignPayload: KeysignPayload? = nil
    @Published var serviceName = ""
    var encryptionKeyHex: String = ""
    
    init() {
        self.vault = Vault(name: "New Vault")
        self.isShowingScanner = false
    }
    
    func setData(vault: Vault, serviceDelegate: ServiceDelegate) {
        self.vault = vault
        self.serviceDelegate = serviceDelegate
        
        if !self.vault.localPartyID.isEmpty {
            self.localPartyID = self.vault.localPartyID
        } else {
            self.localPartyID = Utils.getLocalDeviceIdentity()
        }
    }
    
    func startScan() {
        self.isShowingScanner = true
    }
    
    func joinKeysignCommittee() {
        guard let serverURL = serviceDelegate?.serverURL else {
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
            DispatchQueue.main.async{
                if success {
                    self.logger.info("Successfully joined the keysign committee.")
                    self.status = .WaitingForKeysignToStart
                } else {
                    self.errorMsg = "Failed to join the keysign committee. Please check your connection and try again."
                    self.status = .FailedToStart
                }
            }
        }
    }
    
    func setStatus(status: JoinKeysignStatus) {
        self.status = status
    }
    
    func discoverService() {
        self.netService = NetService(domain: "local.", type: "_http._tcp.", name: self.serviceName)
        self.netService?.delegate = self.serviceDelegate
        self.netService?.resolve(withTimeout: 10)
    }
    func stopJoiningKeysign(){
        self.status = .DiscoverSigningMsg
    }
    func waitForKeysignStart() async {
        do {
            let t = Task {
                repeat {
                    self.checkKeysignStarted()
                    try await Task.sleep(for: .seconds(1))
                } while self.status == .WaitingForKeysignToStart
            }
            try await t.value
        } catch {
            self.logger.error("Failed to wait for keysign to start.")
        }
    }
    
    private func checkKeysignStarted() {
        guard let serverURL = serviceDelegate?.serverURL else {
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
                DispatchQueue.main.async {
                    do {
                        let decoder = JSONDecoder()
                        let peers = try decoder.decode([String].self, from: data)
                        if peers.contains(self.localPartyID) {
                            self.keysignCommittee.append(contentsOf: peers)
                            self.status = .KeysignStarted
                            self.logger.info("Keysign process has started successfully.")
                        }
                    } catch {
                        self.errorMsg = "There was an issue processing the keysign start response. Please try again."
                        self.status = .FailedToStart
                    }
                }
            case .failure(let error):
                let err = error as NSError
                if err.code == 404 {
                    self.logger.info("Waiting for keysign to start. Please stand by.")
                } else {
                    self.errorMsg = "Failed to verify keysign start. Error: \(error.localizedDescription)"
                    self.status = .FailedToStart
                }
            }
        })
    }
    func handleScan(result: Result<ScanResult, ScanError>) {
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
                    self.encryptionKeyHex = keysignMsg.encryptionKeyHex
                    self.logger.info("QR code scanned successfully. Session ID: \(self.sessionID)")
                    self.prepareKeysignMessages(keysignPayload: keysignMsg.payload)
                } catch {
                    self.errorMsg = "Error decoding keysign message: \(error.localizedDescription)"
                    self.status = .FailedToStart
                }
            }
        case .failure(let err):
            self.errorMsg = "QR code scanning failed: \(err.localizedDescription)"
            self.status = .FailedToStart
        }
        self.status = .DiscoverService
    }
    
    func prepareKeysignMessages(keysignPayload: KeysignPayload) {
        let result = keysignPayload.getKeysignMessages(vault: self.vault)
        switch result {
        case .success(let preSignedImageHash):
            self.logger.info("Successfully prepared messages for keysigning.")
            self.keysignMessages = preSignedImageHash.sorted()
            if self.keysignMessages.isEmpty {
                self.errorMsg = "There is no messages to be signed"
                self.status = .FailedToStart
            }
        case .failure(let err):
            self.errorMsg = "Failed to prepare messages for keysigning. Error: \(err.localizedDescription)"
            self.status = .FailedToStart
        }
    }
}
