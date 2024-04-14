//
//  JoinKeygenViewModel.swift
//  VoltixApp
//
//  Created by Johnny Luo on 18/3/2024.
//

import Foundation
import OSLog
import CodeScanner

enum JoinKeygenStatus {
    case DiscoverSessionID
    case DiscoverService
    case JoinKeygen
    case WaitingForKeygenToStart
    case KeygenStarted
    case FailToStart
}

class JoinKeygenViewModel: ObservableObject {
    private let logger = Logger(subsystem: "join-keygen", category: "viewmodel")
    var vault: Vault
    var serviceDelegate: ServiceDelegate?
    
    @Published var tssType: TssType = .Keygen
    @Published var isShowingScanner = false
    @Published var sessionID: String? = nil
    @Published var hexChainCode: String = ""
    
    @Published var netService: NetService? = nil
    @Published var status = JoinKeygenStatus.DiscoverSessionID
    @Published var keygenCommittee = [String]()
    @Published var oldCommittee = [String]()
    @Published var localPartyID: String = ""
    @Published var serviceName = ""
    @Published var errorMessage = ""
    @Published var serverAddress: String? = nil
    var encryptionKeyHex: String = ""
    
    init() {
        self.vault = Vault(name: "New Vault")
    }
    
    func setData(vault: Vault, serviceDelegate: ServiceDelegate) {
        self.vault = vault
        self.serviceDelegate = serviceDelegate
        if !vault.localPartyID.isEmpty {
            self.localPartyID = vault.localPartyID
        } else {
            self.localPartyID = Utils.getLocalDeviceIdentity()
            vault.localPartyID = self.localPartyID
        }
    }
    
    func showBarcodeScanner() {
        isShowingScanner = true
    }
    
    func setStatus(status: JoinKeygenStatus) {
        self.status = status
    }
    
    func discoverService(){
        self.netService = NetService(domain: "local.", type: "_http._tcp.", name: self.serviceName)
        netService?.delegate = self.serviceDelegate
        netService?.resolve(withTimeout: 10)
    }
    
    func joinKeygenCommittee() {
        guard let serverURL = serviceDelegate?.serverURL, let sessionID = sessionID else {
            logger.error("Required information for joining key generation committee is missing.")
            return
        }
        
        let urlString = "\(serverURL)/\(sessionID)"
        let body = [localPartyID]
        Utils.sendRequest(urlString: urlString, method: "POST",headers: TssHelper.getKeygenRequestHeader(), body: body) { success in
            if success {
                self.logger.info("Successfully joined the key generation committee.")
                DispatchQueue.main.async {
                    self.status = .WaitingForKeygenToStart
                }
                
            }
        }
    }
    func stopJoinKeygen(){
        self.status = .DiscoverService
    }
    func waitForKeygenStart() async {
        do{
            let t = Task {
                repeat {
                    checkKeygenStarted()
                    try await Task.sleep(for: .seconds(1))
                } while self.status == .WaitingForKeygenToStart
            }
            try await t.value
        }
        catch{
            logger.error("Failed to wait for keygen to start.")
        }
    }
    private func checkKeygenStarted() {
        guard let serverURL = serviceDelegate?.serverURL, let sessionID = sessionID else {
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
                    DispatchQueue.main.async {
                        if peers.contains(self.localPartyID) {
                            self.keygenCommittee.append(contentsOf: peers)
                            self.status = .KeygenStarted
                        }
                    }
                } catch {
                    self.logger.error("Failed to decode response to JSON: \(data)")
                }
            case .failure(let error):
                self.logger.error("Failed to check if key generation has started, error: \(error)")
            }
        })
    }
    
    func handleScan(result: Result<ScanResult, ScanError>) {
        defer {
            isShowingScanner = false
        }
        var isPremium = false
        switch result {
        case .success(let result):
            guard let scanData = result.string.data(using: .utf8) else {
                errorMessage = "Failed to process scan data."
                status = .FailToStart
                return
            }
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(PeerDiscoveryPayload.self, from: scanData)
                switch result {
                case .Keygen(let keygenMsg):
                    tssType = .Keygen
                    sessionID = keygenMsg.sessionID
                    hexChainCode = keygenMsg.hexChainCode
                    vault.hexChainCode = hexChainCode
                    serviceName = keygenMsg.serviceName
                    encryptionKeyHex = keygenMsg.encryptionKeyHex
                    isPremium = keygenMsg.isPremium
                case .Reshare(let reshareMsg):
                    tssType = .Reshare
                    oldCommittee = reshareMsg.oldParties
                    sessionID = reshareMsg.sessionID
                    hexChainCode = reshareMsg.hexChainCode
                    serviceName = reshareMsg.serviceName
                    encryptionKeyHex = reshareMsg.encryptionKeyHex
                    isPremium = reshareMsg.isPremium
                    // this means the vault is new , and it join the reshare to become the new committee
                    if vault.pubKeyECDSA.isEmpty {
                        vault.hexChainCode = reshareMsg.hexChainCode
                    } else {
                        if vault.pubKeyECDSA != reshareMsg.pubKeyECDSA {
                            errorMessage = "You choose the wrong vault"
                            logger.error("The vault's public key doesn't match the reshare message's public key")
                            status = .FailToStart
                            return
                        }
                    }
                }
                
            } catch {
                errorMessage = "Failed to decode peer discovery message: \(error.localizedDescription)"
                status = .FailToStart
                return
            }
            if isPremium {
                self.serverAddress = Endpoint.voltixRouter
                status = .JoinKeygen
            } else {
                status = .DiscoverService
            }
        case .failure(let error):
            errorMessage = "Failed to scan QR code: \(error.localizedDescription)"
            status = .FailToStart
            return
        }
    }
}
