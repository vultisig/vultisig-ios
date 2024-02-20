//
//  Keysign.swift
//  VoltixApp

import Dispatch
import Foundation
import Mediator
import OSLog
import SwiftUI
import Tss
import WalletCore

private let logger = Logger(subsystem: "keysign", category: "tss")
struct KeysignView: View {
    enum KeysignStatus {
        case CreatingInstance
        case KeysignECDSA
        case KeysignEdDSA
        case KeysignFinished
        case KeysignFailed
    }

    @Binding var presentationStack: [CurrentScreen]
    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let keysignType: KeyType
    let messsageToSign: [String]
    @State var localPartyKey: String
    let keysignPayload: KeysignPayload? // need to pass it along to the next view
    @EnvironmentObject var appState: ApplicationState
    @State private var currentStatus = KeysignStatus.CreatingInstance
    @State private var keysignInProgress = false
    @State private var tssService: TssServiceImpl? = nil
    @State private var tssMessenger: TssMessengerImpl? = nil
    @State private var stateAccess: LocalStateAccessorImpl? = nil
    @State private var keysignError: String? = nil
    @State private var pollingInboundMessages = true
    @State private var signature: String = ""
    @State var cache = NSCache<NSString, AnyObject>()
    @State var signatures = [String: TssKeysignResponse]()

    var body: some View {
        VStack {
            switch self.currentStatus {
            case .CreatingInstance:
                HStack {
                    Text("creating tss instance")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }
            case .KeysignECDSA:
                HStack {
                    Text("Signing using ECDSA key")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }

            case .KeysignEdDSA:
                HStack {
                    Text("Signing using EdDSA key")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }
            case .KeysignFinished:
                VStack {
                    Text("Keysign finished")
                    Text("Signature: \(self.signature)")
                    Button("Done", systemImage: "arrowshape.backward.circle") {}
                }.onAppear {
                    self.pollingInboundMessages = false
                    guard let vault = appState.currentVault else {
                        return
                    }

                    // get bitcoin transaction
                    if let keysignPayload {
                        let result = BitcoinHelper.getSignedBitcoinTransaction(utxos: keysignPayload.utxos, hexPubKey: vault.pubKeyECDSA, fromAddress: keysignPayload.coin.address, toAddress: keysignPayload.toAddress, toAmount: keysignPayload.toAmount, byteFee: keysignPayload.byteFee, signatureProvider: { (preHash: Data) in
                            let hex = preHash.hexString
                            if let sig = self.signatures[hex] {
                                let sigResult =  BitcoinHelper.getSignatureFromTssResponse(tssResponse: sig)
                                switch sigResult {
                                case .success(let sigData):
                                    return sigData
                                case .failure(let err):
                                    logger.error("fail to get signature from TssResponse,error:\(err.localizedDescription)")
                                }
                            }
                            return Data()
                        })
                        switch result {
                        case .success(let tx):
                            print(tx)
                        case .failure(let err):
                            logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
                        }
                    }
                }.navigationBarBackButtonHidden(false)
            case .KeysignFailed:
                Text("Sorry keysign failed, you can retry it,error:\(self.keysignError ?? "")")
                    .navigationBarBackButtonHidden(false)
                    .onAppear {
                        self.pollingInboundMessages = false
                    }
            }
        }.task {
            // Create keygen instance, it takes time to generate the preparams
            guard let vault = appState.currentVault else {
                self.currentStatus = .KeysignFailed
                return
            }
            for msg in self.messsageToSign {
                let msgHash = Utils.getMessageBodyHash(msg: msg)
                self.tssMessenger = TssMessengerImpl(mediatorUrl: self.mediatorURL, sessionID: self.sessionID, messageID: msgHash)
                self.stateAccess = LocalStateAccessorImpl(vault: vault)
                var err: NSError?
                // keysign doesn't need to recreate preparams
                self.tssService = TssNewService(self.tssMessenger, self.stateAccess, false, &err)
                if let err {
                    logger.error("Failed to create TSS instance, error: \(err.localizedDescription)")
                    self.keysignError = err.localizedDescription
                    self.currentStatus = .KeysignFailed
                    return
                }

                // Keep polling for messages
                let t = Task {
                    repeat {
                        if Task.isCancelled { return }
                        self.pollInboundMessages(messageID: msgHash)
                        try await Task.sleep(nanoseconds: 1_000_000_000) // Back off 1s
                    } while self.tssService != nil && self.pollingInboundMessages
                }
                self.keysignInProgress = true
                let keysignReq = TssKeysignRequest()
                keysignReq.localPartyKey = vault.localPartyID
                keysignReq.keysignCommitteeKeys = self.keysignCommittee.joined(separator: ",")
                if let keysignPayload {
                    if keysignPayload.coin.ticker == "BTC" {
                        keysignReq.derivePath = CoinType.bitcoin.derivationPath()
                    }
                }
                // sign messages one by one , since the msg is in hex format , so we need convert it to base64
                // and then pass it to TSS for keysign
                if let msgToSign = Data(hexString: msg)?.base64EncodedString() {
                    keysignReq.messageToSign = msgToSign
                }

                do {
                    switch self.keysignType {
                    case .ECDSA:
                        keysignReq.pubKey = vault.pubKeyECDSA
                        self.currentStatus = .KeysignECDSA
                    case .EdDSA:
                        keysignReq.pubKey = vault.pubKeyEdDSA
                        self.currentStatus = .KeysignEdDSA
                    }
                    if let service = self.tssService {
                        let resp = try await tssKeysign(service: service, req: keysignReq, keysignType: keysignType)
                        // TODO: save the signature with the message it signed
                        self.signature = "R:\(resp.r), S:\(resp.s), RecoveryID:\(resp.recoveryID)"
                    }
                    t.cancel()
                } catch {
                    logger.error("fail to do keysign,error:\(error.localizedDescription)")
                    self.keysignError = error.localizedDescription
                    self.currentStatus = .KeysignFailed
                    return
                }
            }

            self.currentStatus = .KeysignFinished
        }
    }

    private func tssKeysign(service: TssServiceImpl, req: TssKeysignRequest, keysignType: KeyType) async throws -> TssKeysignResponse {
        let t = Task.detached(priority: .high) {
            switch keysignType {
            case .ECDSA:
                return try service.keysignECDSA(req)
            case .EdDSA:
                return try service.keysignEdDSA(req)
            }
        }
        return try await t.value
    }

    private func pollInboundMessages(messageID: String) {
        let urlString = "\(self.mediatorURL)/message/\(self.sessionID)/\(self.localPartyKey)"
        Utils.getRequest(urlString: urlString, headers: ["message_id": messageID], completion: { result in
            switch result {
            case .success(let data):
                do {
                    let decoder = JSONDecoder()
                    let msgs = try decoder.decode([Message].self, from: data)

                    for msg in msgs.sorted(by: { $0.sequenceNo < $1.sequenceNo }) {
                        let key = "\(messageID)-\(self.sessionID)-\(self.localPartyKey)-\(msg.hash)" as NSString
                        if self.cache.object(forKey: key) != nil {
                            logger.info("message with key:\(key) has been applied before")
                            // message has been applied before
                            continue
                        }
                        logger.debug("Got message from: \(msg.from), to: \(msg.to),body:\(msg.body)")
                        try self.tssService?.applyData(msg.body)
                        Task {
                            self.deleteMessageFromServer(hash: msg.hash, messageID: messageID)
                        }
                    }
                } catch {
                    logger.error("Failed to decode response to JSON, data: \(data), error: \(error)")
                }
            case .failure(let error):
                let err = error as NSError
                if err.code != 404 {
                    logger.error("fail to get inbound message,error:\(error.localizedDescription)")
                }
            }
        })
    }

    private func deleteMessageFromServer(hash: String, messageID: String) {
        let urlString = "\(self.mediatorURL)/message/\(self.sessionID)/\(self.localPartyKey)/\(hash)"
        Utils.deleteFromServer(urlString: urlString, messageID: messageID)
    }
}

#Preview {
    KeysignView(presentationStack: .constant([]),
                keysignCommittee: [],
                mediatorURL: "",
                sessionID: "session",
                keysignType: .ECDSA,
                messsageToSign: ["message"],
                localPartyKey: "party id",
                keysignPayload: nil)
}
