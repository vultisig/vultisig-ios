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
    @State private var signature: String = ""
    @State var cache = NSCache<NSString, AnyObject>()
    @State var signatures = [String: TssKeysignResponse]()
    @State private var messagePuller = MessagePuller()

    var body: some View {
        VStack {
            switch self.currentStatus {
            case .CreatingInstance:
                HStack {
                    Text("creating tss instance")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(2)
                }
            case .KeysignECDSA:
                HStack {
                    Text("Signing using ECDSA key")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(2)
                }
                
            case .KeysignEdDSA:
                HStack {
                    Text("Signing using EdDSA key")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(2)
                }
            case .KeysignFinished:
                VStack {
                    Text("Keysign finished")
                    Text("Signature: \(self.signature)")
                    Button("Done", systemImage: "arrowshape.backward.circle") {}
                }.onAppear {
                    self.messagePuller.stop()
                    guard let vault = appState.currentVault else {
                        return
                    }
                    
                    // get bitcoin transaction
                    if let keysignPayload {
                        let bitcoinPubKey = BitcoinHelper.getBitcoinPubKey(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                        let result = BitcoinHelper.getSignedBitcoinTransaction(utxos: keysignPayload.utxos, hexPubKey: bitcoinPubKey, fromAddress: keysignPayload.coin.address, toAddress: keysignPayload.toAddress, toAmount: keysignPayload.toAmount, byteFee: keysignPayload.byteFee, signatureProvider: { (preHash: Data) in
                            let hex = preHash.hexString

                            if let sig = self.signatures[hex] {
                                let sigResult = BitcoinHelper.getSignatureFromTssResponse(tssResponse: sig)
                                switch sigResult {
                                case .success(let sigData):
                                    return sigData
                                case .failure(let err):
                                    switch err {
                                    case BitcoinHelper.BitcoinTransactionError.runtimeError(let errDetail):
                                        logger.error("fail to get signature from TssResponse,error:\(errDetail)")
                                    default:
                                        logger.error("fail to get signature from TssResponse,error:\(err.localizedDescription)")
                                    }
                                }
                            }
                            return Data()
                        })
                        switch result {
                        case .success(let tx):
                            print(tx)
                        case .failure(let err):
                            switch err {
                            case BitcoinHelper.BitcoinTransactionError.runtimeError(let errDetail):
                                logger.error("Failed to get signed transaction,error:\(errDetail)")
                            default:
                                logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
                            }
                        }
                    }
                }.navigationBarBackButtonHidden(false)
            case .KeysignFailed:
                Text("Sorry keysign failed, you can retry it,error:\(self.keysignError ?? "")")
                    .navigationBarBackButtonHidden(false)
                    .onAppear {
                        self.messagePuller.stop()
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
                guard let service = self.tssService else {
                    logger.error("tss service instance is nil")
                    self.currentStatus = .KeysignFailed
                    return
                }
                self.messagePuller.pollMessages(mediatorURL: self.mediatorURL, sessionID: self.sessionID, localPartyKey: self.localPartyKey, tssService: service, messageID: msgHash)
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
                        self.signatures[msg] = resp
                        // TODO: save the signature with the message it signed
                        self.signature = "R:\(resp.r), S:\(resp.s), RecoveryID:\(resp.recoveryID)"
                    }
                    self.messagePuller.stop()
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
