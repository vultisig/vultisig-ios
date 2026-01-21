//
//  KeysignDiscoveryViewModel.swift
//  VultisigApp
//

import Foundation
import Combine
import Mediator
import OSLog
import SwiftUI

enum KeysignDiscoveryStatus {
    case WaitingForDevices
    case WaitingForFast
    case FailToStart
}

class KeysignDiscoveryViewModel: ObservableObject {
    private let logger = Logger(subsystem: "keysign-discovery", category: "viewmodel")
    private var cancellables = Set<AnyCancellable>()
    
    var vault: Vault
    var keysignPayload: KeysignPayload?
    var customMessagePayload: CustomMessagePayload?
    var participantDiscovery: ParticipantDiscovery?
    var encryptionKeyHex: String?
    
    private let mediator = Mediator.shared
    private let fastVaultService = FastVaultService.shared
    
    @Published var serverAddr = "http://127.0.0.1:18080"
    @Published var selections = Set<String>()
    @Published var sessionID = ""
    @Published var status = KeysignDiscoveryStatus.WaitingForDevices
    @Published var localPartyID = ""
    @Published var keysignMessages = [String]()
    @Published var serviceName = ""
    @Published var errorMessage = ""
    
    init() {
        self.vault = Vault(name: "Main Vault")
        self.keysignPayload = KeysignPayload(
            coin: Coin.example,
            toAddress: "",
            toAmount: 0,
            chainSpecific: BlockChainSpecific.UTXO(byteFee: 0, sendMaxAmount: false),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )
        self.participantDiscovery = nil
        self.encryptionKeyHex = Encryption.getEncryptionKey()
        if VultisigRelay.IsRelayEnabled {
            serverAddr = Endpoint.vultisigRelay
        }
    }
    
    @MainActor
    func setData(
        vault: Vault,
        keysignPayload: KeysignPayload?,
        customMessagePayload: CustomMessagePayload?,
        participantDiscovery: ParticipantDiscovery,
        fastVaultPassword: String?,
        onFastKeysign: (() -> Void)?
    ) async {
        self.vault = vault
        self.keysignPayload = keysignPayload
        self.customMessagePayload = customMessagePayload
        self.participantDiscovery = participantDiscovery
        
        if self.sessionID.isEmpty {
            self.sessionID = UUID().uuidString
        }
        if self.serviceName.isEmpty {
            self.serviceName = "Vultisig-" + Int.random(in: 1 ... 1000).description
        }
        if !self.vault.localPartyID.isEmpty {
            self.localPartyID = self.vault.localPartyID
        } else {
            self.localPartyID = Utils.getLocalDeviceIdentity()
        }
        self.selections.insert(self.localPartyID)
        // mediator server need to be
        self.mediator.start(name: self.serviceName)
        
        var coin: Coin?
        if let keysignPayload {
            do {
                // Refresh Solana blockhash BEFORE generating messages to ensure both devices
                // (including Fast Vault server) use the same fresh blockhash
                var finalPayload = keysignPayload
                if keysignPayload.coin.chain == .solana {
                    finalPayload = try await BlockChainService.shared.refreshSolanaBlockhash(for: keysignPayload)
                    self.keysignPayload = finalPayload
                    logger.info("Refreshed Solana blockhash before generating keysign messages")
                }
                
                let keysignFactory = KeysignMessageFactory(payload: finalPayload)
                let preSignedImageHash = try keysignFactory.getKeysignMessages(vault: vault)
                self.keysignMessages = preSignedImageHash.sorted()
                coin = keysignPayload.coin
            } catch {
                self.logger.error("Failed to get preSignedImageHash: \(error)")
                self.errorMessage = error.localizedDescription
                self.status = .FailToStart
            }
        }
        
        if let customMessagePayload {
            self.keysignMessages = customMessagePayload.keysignMessages
            coin = vault.nativeCoin(for: Chain(name: customMessagePayload.chain) ?? .ethereum)
        }
        
        if keysignMessages.isEmpty {
            logger.error("no meessage need to be signed")
            status = .FailToStart
        }
        
        if let fastVaultPassword, let coin {
            // when fast sign , always using relay server
            serverAddr = Endpoint.vultisigRelay
            
            if vault.signers.count <= 3 {
                // skip device lookup if possible
                status = .WaitingForFast
            }
            
            fastVaultService.sign(
                publicKeyEcdsa: vault.pubKeyECDSA,
                keysignMessages: self.keysignMessages,
                sessionID: self.sessionID,
                hexEncryptionKey: self.encryptionKeyHex!,
                derivePath: coin.coinType.derivationPath(),
                isECDSA: coin.chain.isECDSA,
                vaultPassword: fastVaultPassword,
                chain: coin.chain.name
            ) { isSuccess in
                if !isSuccess {
                    self.logger.error("Fast Vault signing failed")
                    self.status = .FailToStart
                    self.errorMessage = "Fast Vault signing failed. Please check your password or try Paired Sign by long-pressing the button."
                } else {
                    self.logger.info("Fast Vault signing initiated successfully")
                }
            }
            
            cancellables.forEach { $0.cancel() }
            
            participantDiscovery.$peersFound
                .removeDuplicates()
                .filter { !$0.isEmpty }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                guard let self else { return }
                if $0.count == 0 {
                    return
                }
                $0.forEach { peer in
                    self.handleSelection(peer)
                }
                self.startFastKeysignIfNeeded(vault: vault, onFastKeysign: onFastKeysign)
            }
            .store(in: &cancellables)
        }
    }
    
    func startDiscovery() async {
        
        self.logger.info("mediator server started")
        self.startKeysignSession()
        self.participantDiscovery?.getParticipants(
            serverAddr: self.serverAddr,
            sessionID: self.sessionID,
            localParty: self.localPartyID,
            pubKeyECDSA: vault.pubKeyECDSA
        )
    }
    
    func handleSelection(_ peer: String) {
        if selections.contains(peer) {
            // Don't remove itself
            if peer != localPartyID {
                selections.remove(peer)
            }
        } else {
            selections.insert(peer)
        }
    }
    
    func startFastKeysignIfNeeded(vault: Vault, onFastKeysign: (() -> Void)?) {
        guard isValidPeers(vault: vault) else { return }
        onFastKeysign?()
    }
    
    func isValidPeers(vault: Vault) -> Bool {
        return selections.count >= (vault.getThreshold() + 1)
    }
    
    @MainActor func startKeysign(vault: Vault) -> KeysignInput {
        kickoffKeysign(allParticipants: self.selections.map { $0 })
        participantDiscovery?.stop()

        return KeysignInput(
            vault: vault,
            keysignCommittee: selections.map { $0 },
            mediatorURL: serverAddr,
            sessionID: sessionID,
            keysignType: keysignType,
            messsageToSign: keysignMessages, // need to figure out all the prekeysign hashes
            keysignPayload: keysignPayload,
            customMessagePayload: customMessagePayload,
            encryptionKeyHex: encryptionKeyHex ?? "",
            isInitiateDevice: true
        )
    }
    
    func kickoffKeysign(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        Utils.sendRequest(urlString: urlString,
                          method: "POST",
                          headers: nil,
                          body: allParticipants) { _ in
            self.logger.info("kicked off keysign successfully")
        }
    }
    
    func stopDiscovery() {
        self.participantDiscovery?.stop()
    }
    
    func restartParticipantDiscovery() {
        self.participantDiscovery?.stop()
        if VultisigRelay.IsRelayEnabled {
            serverAddr = Endpoint.vultisigRelay
        } else {
            serverAddr = "http://127.0.0.1:18080"
        }
        self.participantDiscovery?.peersFound = [String]()
        self.startKeysignSession()
        self.participantDiscovery?.getParticipants(serverAddr: self.serverAddr,
                                                   sessionID: self.sessionID,
                                                   localParty: self.localPartyID,
                                                   pubKeyECDSA: vault.pubKeyECDSA)
    }
    private func startKeysignSession() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        let body = [self.localPartyID]
        Utils.sendRequest(urlString: urlString,
                          method: "POST",
                          headers: nil,
                          body: body) { success in
            if success {
                self.logger.info("Started session successfully.")
            } else {
                self.logger.info("Failed to start session.")
            }
        }
    }
    
    func getQrImage(size: CGFloat) async -> (String, Image)? {
        guard let qrCodeData = await generateQRdata() else {
            return nil
        }
        return (qrCodeData, Utils.generateQRCodeImage(from: qrCodeData))
    }
    
    private func generateQRdata() async -> String? {
        do {
            guard let encryptionKeyHex = self.encryptionKeyHex else {
                logger.error("encryption key is nil")
                return nil
            }
            let message = KeysignMessage(
                sessionID: sessionID,
                serviceName: serviceName,
                payload: keysignPayload,
                customMessagePayload: customMessagePayload,
                encryptionKeyHex: encryptionKeyHex,
                useVultisigRelay: VultisigRelay.IsRelayEnabled,
                payloadID: ""
            )
            let protoKeysignMsg = try ProtoSerializer.serialize(message)
            let payloadService = PayloadService(serverURL: serverAddr)
            var jsonData = ""
            
            if let keysignPayload, payloadService.shouldUploadToRelay(payload: protoKeysignMsg) {
                let keysignPayload = try ProtoSerializer.serialize(keysignPayload)
                let hash = try await payloadService.uploadPayload(payload: keysignPayload)
                let messageWithoutPayload = KeysignMessage(sessionID: sessionID,
                                                           serviceName: serviceName,
                                                           payload: nil,
                                                           customMessagePayload: nil,
                                                           encryptionKeyHex: encryptionKeyHex,
                                                           useVultisigRelay: VultisigRelay.IsRelayEnabled,
                                                           payloadID: hash)
                jsonData = try ProtoSerializer.serialize(messageWithoutPayload)
                
            } else {
                jsonData = protoKeysignMsg
            }
            return "https://vultisig.com?type=SignTransaction&vault=\(vault.pubKeyECDSA)&jsonData=\(jsonData)"
        } catch {
            logger.error("fail to encode keysign messages to json,error:\(error)")
            return nil
        }
    }
    
    private var keysignType: KeyType {
        if let keysignPayload {
            return keysignPayload.coin.chain.signingKeyType
        } else {
            return .ECDSA
        }
    }
}
