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
    var keysignPayload: KeysignPayload
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
        self.keysignPayload = KeysignPayload(coin: Coin.example, toAddress: "", toAmount: 0, chainSpecific: BlockChainSpecific.UTXO(byteFee: 0, sendMaxAmount: false), utxos: [], memo: nil, swapPayload: nil, approvePayload: nil, vaultPubKeyECDSA: vault.pubKeyECDSA, vaultLocalPartyID: vault.localPartyID)
        self.participantDiscovery = nil
        self.encryptionKeyHex = Encryption.getEncryptionKey()
        if VultisigRelay.IsRelayEnabled {
            serverAddr = Endpoint.vultisigRelay
        }
    }
    
    func setData(
        vault: Vault,
        keysignPayload: KeysignPayload,
        participantDiscovery: ParticipantDiscovery,
        fastVaultPassword: String?,
        onFastKeysign: (() -> Void)?
    ) {
        self.vault = vault
        self.keysignPayload = keysignPayload
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
        
        do {
            let keysignFactory = KeysignMessageFactory(payload: keysignPayload)
            let preSignedImageHash = try keysignFactory.getKeysignMessages(vault: vault)
            self.keysignMessages = preSignedImageHash.sorted()

            if self.keysignMessages.isEmpty {
                self.logger.error("no meessage need to be signed")
                self.status = .FailToStart
            }

            if let fastVaultPassword {
                self.status = .WaitingForFast
                
                self.fastVaultService.sign(
                    publicKeyEcdsa: vault.pubKeyECDSA,
                    keysignMessages: self.keysignMessages,
                    sessionID: self.sessionID,
                    hexEncryptionKey: self.encryptionKeyHex!,
                    derivePath: keysignPayload.coin.coinType.derivationPath(),
                    isECDSA: keysignPayload.coin.chain.isECDSA,
                    vaultPassword: fastVaultPassword
                ) { isSuccess in
                    if !isSuccess {
                        self.status = .FailToStart
                    }
                }

                cancellables.forEach { $0.cancel() }

                participantDiscovery.$peersFound.sink { [weak self] in
                        $0.forEach { peer in
                            self?.handleSelection(peer)
                        }
                        self?.startFastKeysignIfNeeded(vault: vault, onFastKeysign: onFastKeysign)
                    }
                    .store(in: &cancellables)
            }
        } catch {
            self.logger.error("Failed to get preSignedImageHash: \(error)")
            self.errorMessage = error.localizedDescription
            self.status = .FailToStart
        }
    }
    
    func startDiscovery() async {
        self.mediator.start(name: self.serviceName)
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

    @MainActor func startKeysign(vault: Vault, viewModel: TransferViewModel) -> KeysignView {
        kickoffKeysign(allParticipants: self.selections.map { $0 })
        participantDiscovery?.stop()
        viewModel.moveToNextView()
        
        return KeysignView(
            vault: vault,
            keysignCommittee: selections.map { $0 },
            mediatorURL: serverAddr,
            sessionID: sessionID,
            keysignType: keysignPayload.coin.chain.signingKeyType,
            messsageToSign: keysignMessages, // need to figure out all the prekeysign hashes
            keysignPayload: keysignPayload,
            transferViewModel: viewModel,
            encryptionKeyHex: encryptionKeyHex ?? ""
        )
    }
    
    func kickoffKeysign(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        Utils.sendRequest(urlString: urlString,
                          method: "POST",
                          headers: TssHelper.getKeysignRequestHeader(pubKey: vault.pubKeyECDSA),
                          body: allParticipants) { _ in
            self.logger.info("kicked off keysign successfully")
        }
    }
    
    func stopDiscovery() {
        self.participantDiscovery?.stop()
    }
    
    func restartParticipantDiscovery(){
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
                          headers: TssHelper.getKeysignRequestHeader(pubKey: vault.pubKeyECDSA),
                          body: body) { success in
            if success {
                self.logger.info("Started session successfully.")
            } else {
                self.logger.info("Failed to start session.")
            }
        }
    }
    
    func getQrImage(size: CGFloat) -> Image {
        guard let encryptionKeyHex = self.encryptionKeyHex else {
            logger.error("encryption key is nil")
            return Image(systemName: "xmark")
        }
        let message = KeysignMessage(
            sessionID: sessionID,
            serviceName: serviceName,
            payload: keysignPayload,
            encryptionKeyHex: encryptionKeyHex,
            useVultisigRelay: VultisigRelay.IsRelayEnabled
        )
        do {
            let payload = try ProtoSerializer.serialize(message)
            let data = "vultisig://vultisig.com?type=SignTransaction&vault=\(vault.pubKeyECDSA)&jsonData=\(payload)"
            return Utils.generateQRCodeImage(from: data)
        } catch {
            logger.error("fail to encode keysign messages to json,error:\(error)")
            return Image(systemName: "xmark")
        }
    }
    
}
