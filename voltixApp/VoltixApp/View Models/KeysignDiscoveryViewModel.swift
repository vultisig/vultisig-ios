//
//  KeysignDiscoveryViewModel.swift
//  VoltixApp
//

import Foundation
import Mediator
import OSLog

enum KeysignDiscoveryStatus {
    case WaitingForDevices
    case FailToStart
}

class KeysignDiscoveryViewModel: ObservableObject {
    private let logger = Logger(subsystem: "keysign-discovery", category: "viewmodel")
    var vault: Vault
    var keysignPayload: KeysignPayload
    var participantDiscovery: ParticipantDiscovery?

    private let mediator = Mediator.shared

    let serverAddr = "http://127.0.0.1:8080"
    @Published var selections = Set<String>()
    @Published var sessionID = ""
    @Published var status = KeysignDiscoveryStatus.WaitingForDevices
    @Published var localPartyID = ""
    @Published var keysignMessages = [String]()
    @Published var serviceName = ""
    @Published var errorMessage = ""

    init() {
        self.vault = Vault(name: "New Vault")
        self.keysignPayload = KeysignPayload(coin: Coin.example, toAddress: "", toAmount: 0, chainSpecific: BlockChainSpecific.UTXO(byteFee: 0), utxos: [], memo: nil, swapPayload: nil)
        self.participantDiscovery = nil
    }

    func setData(vault: Vault, keysignPayload: KeysignPayload, participantDiscovery: ParticipantDiscovery) {
        self.vault = vault
        self.keysignPayload = keysignPayload
        self.participantDiscovery = participantDiscovery
        if self.sessionID.isEmpty {
            self.sessionID = UUID().uuidString
        }
        if self.serviceName.isEmpty {
            self.serviceName = "VoltixApp-" + Int.random(in: 1 ... 1000).description
        }
        if !self.vault.localPartyID.isEmpty {
            self.localPartyID = self.vault.localPartyID
        } else {
            self.localPartyID = Utils.getLocalDeviceIdentity()
        }

        let keysignMessageResult = self.keysignPayload.getKeysignMessages(vault: self.vault)
        switch keysignMessageResult {
        case .success(let preSignedImageHash):
            self.keysignMessages = preSignedImageHash
            if self.keysignMessages.isEmpty {
                self.logger.error("no meessage need to be signed")
                self.status = .FailToStart
            }
        case .failure(let err):
            self.logger.error("Failed to get preSignedImageHash: \(err)")
            self.status = .FailToStart
        }
    }

    func startDiscovery() {
        self.mediator.start(name: self.serviceName)
        self.logger.info("mediator server started")
        self.startKeysignSession()
        self.participantDiscovery?.getParticipants(serverAddr: self.serverAddr, sessionID: self.sessionID)
    }
    
    @MainActor func startKeysign(vault: Vault, viewModel: SendCryptoViewModel) -> KeysignView {
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
            sendCryptoViewModel: viewModel
        )
    }
    
    func kickoffKeysign(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        Utils.sendRequest(urlString: urlString, method: "POST", body: allParticipants) { _ in
            self.logger.info("kicked off keysign successfully")
        }
    }
    func stopDiscovery() {
        self.participantDiscovery?.stop()
    }

    private func startKeysignSession() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        let body = [self.localPartyID]
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                self.logger.info("Started session successfully.")
            } else {
                self.logger.info("Failed to start session.")
            }
        }
    }
}
