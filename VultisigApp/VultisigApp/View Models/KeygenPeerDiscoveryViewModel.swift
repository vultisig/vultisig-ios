//
//  KeygenPeerDiscoveryViewModel.swift
//  VultisigApp
//

import Foundation
import Mediator
import OSLog
import SwiftUI
import Combine

enum PeerDiscoveryStatus {
    case WaitingForDevices
    case Keygen
    case Failure
}

class KeygenPeerDiscoveryViewModel: ObservableObject {
    
    private let logger = Logger(subsystem: "peers-discory-viewmodel", category: "communication")
    
    var tssType: TssType
    var vault: Vault
    var participantDiscovery: ParticipantDiscovery?
    var encryptionKeyHex: String?
    var chains: [Chain]?
    
    @Published var status = PeerDiscoveryStatus.WaitingForDevices
    @Published var serviceName = ""
    @Published var errorMessage = ""
    @Published var sessionID = ""
    @Published var localPartyID = ""
    @Published var selections = Set<String>()
    @Published var keygenCommittee = [String]()
    @Published var serverAddr = "http://127.0.0.1:18080"
    @Published var selectedNetwork = VultisigRelay.IsRelayEnabled ? NetworkPromptType.Internet : NetworkPromptType.Local {
        didSet {
            print("selected network changed: \(selectedNetwork)")
            VultisigRelay.IsRelayEnabled = NetworkPromptType.Internet == selectedNetwork
        }
    }
    @Published var isLoading: Bool = false
    
    private var peersFoundCancellable: AnyCancellable?
    private let mediator = Mediator.shared
    private let fastVaultService = FastVaultService.shared
    
    init() {
        self.tssType = .Keygen
        self.vault = Vault(name: "Main Vault")
        self.status = .WaitingForDevices
        self.participantDiscovery = nil
        self.encryptionKeyHex = Encryption.getEncryptionKey()
        
        if VultisigRelay.IsRelayEnabled {
            serverAddr = Endpoint.vultisigRelay
            selectedNetwork = .Internet
        } else {
            serverAddr = "http://127.0.0.1:18080"
            selectedNetwork = .Local
        }
    }
    
    func setData(
        vault: Vault,
        tssType: TssType,
        state: SetupVaultState,
        participantDiscovery: ParticipantDiscovery,
        fastSignConfig: FastSignConfig?,
        chains: [Chain]?
    ) {
        self.isLoading = true
        self.setupPeersFoundCancellable(
            state: state,
            participantDiscovery: participantDiscovery
        )
        self.vault = vault
        self.tssType = tssType
        self.participantDiscovery = participantDiscovery
        self.chains = chains
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
        
        self.restartSelections()
        // ensure when active / fast vault , user is always using internet option
        switch state {
        case .active , .fast:
            VultisigRelay.IsRelayEnabled = true
            selectedNetwork = .Internet
            serverAddr = Endpoint.vultisigRelay
        case .secure:
            break
        }
        if let config = fastSignConfig {
            switch tssType {
            case .Keygen:
                fastVaultService.create(name: vault.name,
                                        sessionID: sessionID,
                                        hexEncryptionKey: encryptionKeyHex!,
                                        hexChainCode: vault.hexChainCode,
                                        encryptionPassword: config.password,
                                        email: config.email,
                                        lib_type: vault.libType == .DKLS ? 1 : 0)
            case .KeyImport:
                fastVaultService.keyImport(name: vault.name,
                                           sessionID: sessionID,
                                           hexEncryptionKey: encryptionKeyHex!,
                                           hexChainCode: vault.hexChainCode,
                                           encryptionPassword: config.password,
                                           email: config.email,
                                           lib_type: 2,
                                           chains: chains?.map { $0.name } ?? [])
            case .Reshare:
                let pubKeyECDSA = config.isExist ? vault.pubKeyECDSA : .empty
                fastVaultService.reshare(name: vault.name,
                                         publicKeyECDSA: pubKeyECDSA,
                                         sessionID: sessionID,
                                         hexEncryptionKey: encryptionKeyHex!,
                                         hexChainCode: vault.hexChainCode,
                                         encryptionPassword: config.password,
                                         email: config.email,
                                         oldParties: vault.signers,
                                         oldResharePrefix: vault.resharePrefix ?? "",
                                         lib_type: vault.libType == .DKLS ? 1 : 0)
            case .Migrate:
                fastVaultService.migrate(publicKeyECDSA:vault.pubKeyECDSA, sessionID: sessionID, hexEncryptionKey: encryptionKeyHex!, encryptionPassword: config.password, email: config.email)
            }
        }
        self.isLoading = false
    }
    
    func setupPeersFoundCancellable(
        state: SetupVaultState,
        participantDiscovery: ParticipantDiscovery
    ) {
        peersFoundCancellable?.cancel()
        peersFoundCancellable = nil
        peersFoundCancellable = participantDiscovery.$peersFound
            .removeDuplicates()
            .filter{!$0.isEmpty}
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                if $0.count == 0 {
                    return
                }
                        
                $0.forEach { peer in
                    self.autoSelectPeer(peer)
                }
                self.startFastVaultKeygenIfNeeded(state: state)
            }
    }
    
    func restartSelections() {
        self.selections.removeAll()
        self.selections.insert(self.localPartyID)
    }
    
    func autoSelectPeer(_ peer: String){
        if !selections.contains(peer) {
            selections.insert(peer)
        }
    }
    
    func handleSelection(_ peer: String) {
        withAnimation {
            if selections.contains(peer) {
                if peer != localPartyID {
                    selections.remove(peer)
                }
            } else {
                selections.insert(peer)
            }
        }
    }
    
    var isLookingForDevices: Bool {
        return status == .WaitingForDevices && selections.count < 2
    }
    
    func startFastVaultKeygenIfNeeded(state: SetupVaultState) {
        guard isValidPeers(state: state), !state.hasOtherDevices else { return }
        startKeygen()
    }
    
    func isValidPeers(state: SetupVaultState) -> Bool {
        guard state.isFastVault else {
            return true
        }
        let isValid = selections.contains(where: { $0.contains("Server-") })
        return isValid
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
    
    func restartParticipantDiscovery() {
        self.participantDiscovery?.stop()
        if VultisigRelay.IsRelayEnabled {
            serverAddr = Endpoint.vultisigRelay
        } else {
            serverAddr = "http://127.0.0.1:18080"
        }
        self.restartSelections()
        self.participantDiscovery?.peersFound = [String]()
        self.startSession()
        self.participantDiscovery?.getParticipants(
            serverAddr: self.serverAddr,
            sessionID: self.sessionID,
            localParty: self.localPartyID,
            pubKeyECDSA: vault.pubKeyECDSA
        )
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
        
        self.logger.info("starting session with url:\(urlString), body:\(body)")
        Utils.sendRequest(urlString: urlString, method: "POST",headers: nil, body: body) { success in
            if success {
                self.logger.info("Started session successfully.")
            } else {
                self.logger.info("Failed to start session.")
            }
        }
    }
    


    private func startKeygen(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        
        // Enforce deterministic order (assumes calling device is the initiator): local device first, then peers by discovery order
        var sortedParticipants = [String]()
        
        // Always add self first if selected
        if self.selections.contains(self.localPartyID) {
            sortedParticipants.append(self.localPartyID)
        }
        
        // Add discovered peers in order
        if let discoveredPeers = self.participantDiscovery?.peersFound {
            for peer in discoveredPeers {
                if self.selections.contains(peer) {
                    sortedParticipants.append(peer)
                }
            }
        }
        
        // Fallback: If there are any selected peers not in discovery list (edge case), add them
        for peer in allParticipants {
            if !sortedParticipants.contains(peer) {
                sortedParticipants.append(peer)
            }
        }
        
        self.keygenCommittee = sortedParticipants
        
        Utils.sendRequest(urlString: urlString, method: "POST",headers:nil, body: sortedParticipants) { _ in
            self.logger.info("kicked off keygen successfully")
        }
    }
    
    func getQRCodeData(size: CGFloat, displayScale: CGFloat) -> (String, Image)? {
        guard
            let qrCodeData = generateQRdata(),
            let image = QRCodeGenerator().generateImage(
                qrStringData: qrCodeData,
                size: CGSize(width: size, height: size),
                scale: displayScale,
                bgColor: Theme.colors.bgSurface1
            )
        else {
            return nil
        }
        
        return (qrCodeData, image)
    }
    
    private func generateQRdata() -> String? {
        do {
            guard let encryptionKeyHex else { return nil }
            switch tssType {
            case .Keygen, .KeyImport:
                let keygenMsg = KeygenMessage(
                    sessionID: sessionID,
                    hexChainCode: vault.hexChainCode,
                    serviceName: serviceName,
                    encryptionKeyHex: encryptionKeyHex,
                    useVultisigRelay: VultisigRelay.IsRelayEnabled,
                    vaultName: vault.name,
                    libType: vault.libType ?? .GG20,
                    chains: chains ?? []
                )
                let data = try ProtoSerializer.serialize(keygenMsg)
                return "https://vultisig.com?type=NewVault&tssType=\(tssType.rawValue)&jsonData=\(data)"
            case .Reshare, .Migrate:
                let reshareMsg = ReshareMessage(
                    sessionID: sessionID,
                    hexChainCode: vault.hexChainCode,
                    serviceName: serviceName,
                    pubKeyECDSA: vault.pubKeyECDSA,
                    oldParties: vault.signers,
                    encryptionKeyHex: encryptionKeyHex,
                    useVultisigRelay: VultisigRelay.IsRelayEnabled,
                    oldResharePrefix: vault.resharePrefix ?? "",
                    vaultName: vault.name,
                    libType: vault.libType ?? .GG20
                )
                let data = try ProtoSerializer.serialize(reshareMsg)
                return "https://vultisig.com?type=NewVault&tssType=\(tssType.rawValue)&jsonData=\(data)"
            }
        } catch {
            logger.error("fail to encode keygen message to json,error:\(error.localizedDescription)")
            return nil
        }
    }
}
