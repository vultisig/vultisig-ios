//
//  KeygenPeerDiscoveryViewModel.swift
//  VultisigApp
//

import Foundation
import Mediator
import OSLog
import SwiftUI

enum PeerDiscoveryStatus {
    case WaitingForDevices
    case Summary
    case Keygen
    case Failure
}

class KeygenPeerDiscoveryViewModel: ObservableObject {
    private let logger = Logger(subsystem: "peers-discory-viewmodel", category: "communication")
    var tssType: TssType
    var vault: Vault
    var participantDiscovery: ParticipantDiscovery?
    var encryptionKeyHex: String?
    
    @Published var status = PeerDiscoveryStatus.WaitingForDevices
    @Published var serviceName = ""
    @Published var errorMessage = ""
    @Published var sessionID = ""
    @Published var localPartyID = ""
    @Published var selections = Set<String>()
    @Published var serverAddr = "http://127.0.0.1:18080"
    @Published var vaultDetail = String.empty
    @Published var selectedNetwork = NetworkPromptType.Internet
    
    private let mediator = Mediator.shared
    
    init() {
        self.tssType = .Keygen
        self.vault = Vault(name: "Main Vault")
        self.status = .WaitingForDevices
        self.participantDiscovery = nil
        self.encryptionKeyHex = Encryption.getEncryptionKey()
        if VultisigRelay.IsRelayEnabled {
            serverAddr = Endpoint.vultisigRelay
            selectedNetwork = .Internet
        }
    }
    
    func setData(vault: Vault, tssType: TssType, participantDiscovery: ParticipantDiscovery) {
        self.vault = vault
        self.tssType = tssType
        self.participantDiscovery = participantDiscovery
        
        if self.sessionID.isEmpty {
            self.sessionID = UUID().uuidString
        }
        
        if self.serviceName.isEmpty {
            self.serviceName = "VultisigApp-" + Int.random(in: 1 ... 1000).description
        }
        
        if self.vault.hexChainCode.isEmpty {
            guard let chainCode = Utils.getChainCode() else {
                self.logger.error("fail to get chain code")
                self.status = .Failure
                return
            }
            self.vault.hexChainCode = chainCode
        }
        
        if !self.vault.localPartyID.isEmpty {
            self.localPartyID = vault.localPartyID
        } else {
            self.localPartyID = Utils.getLocalDeviceIdentity()
            self.vault.localPartyID = self.localPartyID
        }
        self.selections.insert(self.localPartyID)
        switch tssType {
        case .Keygen:
            startVultisigner(name: vault.name, sessionID: sessionID, hexEncryptionKey: self.encryptionKeyHex!, hexChainCode: vault.hexChainCode, localPartyID: "signer-1", encryptionPassword: "test123", email: "johnnyluo1980@icloud.com")
        case .Reshare:
            startVultisignerReshare(name: vault.name, publicKeyECDSA: vault.pubKeyECDSA, sessionID: sessionID, hexEncryptionKey: self.encryptionKeyHex!, hexChainCode: vault.hexChainCode, localPartyID: "signer-1", encryptionPassword: "test123", email: "johnny@vultisig.com")
        }
    }
    func startVultisignerReshare(name: String,
                                 publicKeyECDSA: String,
                          sessionID: String,
                          hexEncryptionKey: String,
                          hexChainCode: String,
                          localPartyID:String,
                          encryptionPassword:String,
                          email: String){
        let req = ReshareRequest(name: name,public_key: publicKeyECDSA, session_id: sessionID, hex_encryption_key: hexEncryptionKey, hex_chain_code: hexChainCode, local_party_id: localPartyID, encryption_password: encryptionPassword, email: email)
        
        let urlString = "https://api.vultisig.com/vault/reshare"
        Utils.sendRequest(urlString: urlString, method: "POST", headers: [:], body: req){ _ in
            print("send req to vultisigner successfully")
        }
        
    }
    func startVultisigner(name:String,
                          sessionID: String,
                          hexEncryptionKey: String,
                          hexChainCode: String,
                          localPartyID:String,
                          encryptionPassword:String,
                          email: String){
        let req = VaultCreateRequest(name: name, session_id: sessionID, hex_encryption_key: hexEncryptionKey, hex_chain_code: hexChainCode, local_party_id: localPartyID, encryption_password: encryptionPassword, email: email)
        
        let urlString = "https://api.vultisig.com/vault/create"
        Utils.sendRequest(urlString: urlString, method: "POST", headers: [:], body: req){ _ in
            print("send req to vultisigner successfully")
        }
        
    }
    
    func startDiscovery() {
        self.mediator.start(name: self.serviceName)
        self.logger.info("mediator server started")
        self.startSession()
        self.participantDiscovery?.getParticipants(serverAddr: self.serverAddr,
                                                   sessionID: self.sessionID,
                                                   localParty: self.localPartyID,
                                                   pubKeyECDSA: vault.pubKeyECDSA)
    }
    
    func restartParticipantDiscovery(){
        self.participantDiscovery?.stop()
        if VultisigRelay.IsRelayEnabled {
            serverAddr = Endpoint.vultisigRelay
        } else {
            serverAddr = "http://127.0.0.1:18080"
        }
        self.participantDiscovery?.peersFound = [String]()
        self.startSession()
        self.participantDiscovery?.getParticipants(serverAddr: self.serverAddr,
                                                   sessionID: self.sessionID,
                                                   localParty: self.localPartyID,
                                                   pubKeyECDSA: vault.pubKeyECDSA)
    }
    
    func showSummary() {
        self.status = .Summary
    }
    
    func startKeygen() {
        self.startKeygen(allParticipants: self.selections.map { $0 })
        self.status = .Keygen
        self.participantDiscovery?.stop()
    }
    
    func stopMediator() {
        self.logger.info("mediator server stopped")
        self.participantDiscovery?.stop()
        self.mediator.stop()
    }
    
    
    private func startSession() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        let body = [self.localPartyID]
        
        Utils.sendRequest(urlString: urlString, method: "POST",headers:TssHelper.getKeygenRequestHeader(), body: body) { success in
            if success {
                self.logger.info("Started session successfully.")
            } else {
                self.logger.info("Failed to start session.")
            }
        }
    }
    
    private func startKeygen(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        
        Utils.sendRequest(urlString: urlString, method: "POST",headers:TssHelper.getKeygenRequestHeader(), body: allParticipants) { _ in
            self.logger.info("kicked off keygen successfully")
        }
    }
    
    func getQrImage(size: CGFloat) -> Image {
        guard let encryptionKeyHex else {return Image(systemName: "xmark")}
        let jsonData: String
        do {
            switch tssType {
            case .Keygen:
                let keygenMsg = KeygenMessage(
                    sessionID: sessionID,
                    hexChainCode: vault.hexChainCode,
                    serviceName: serviceName,
                    encryptionKeyHex: encryptionKeyHex,
                    useVultisigRelay: VultisigRelay.IsRelayEnabled,
                    vaultName: vault.name
                )
                let data = try ProtoSerializer.serialize(keygenMsg)
                jsonData = "vultisig://vultisig.com?type=NewVault&tssType=\(TssType.Keygen.rawValue)&jsonData=\(data)"
            case .Reshare:
                let reshareMsg = ReshareMessage(
                    sessionID: sessionID,
                    hexChainCode: vault.hexChainCode,
                    serviceName: serviceName,
                    pubKeyECDSA: vault.pubKeyECDSA,
                    oldParties: vault.signers,
                    encryptionKeyHex: encryptionKeyHex,
                    useVultisigRelay: VultisigRelay.IsRelayEnabled,
                    oldResharePrefix: vault.resharePrefix ?? "",
                    vaultName: vault.name
                )
                let data = try ProtoSerializer.serialize(reshareMsg)
                jsonData = "vultisig://vultisig.com?type=NewVault&tssType=\(TssType.Reshare.rawValue)&jsonData=\(data)"
            }
            return Utils.generateQRCodeImage(from: jsonData)
        } catch {
            logger.error("fail to encode keygen message to json,error:\(error.localizedDescription)")
            return Image(systemName: "xmark")
        }
    }
    
    
}
