//
//  Keysign.swift
//  VoltixApp

import CryptoKit
import Foundation
import Mediator
import OSLog
import SwiftData
import SwiftUI
import Tss

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
    let messsageToSign: String
    @State var localPartyKey: String
    @EnvironmentObject var appState: ApplicationState
    @State private var currentStatus = KeysignStatus.CreatingInstance
    @State private var keysignInProgress = false
    @State private var tssService: TssServiceImpl? = nil
    @State private var tssMessenger: TssMessengerImpl? = nil
    @State private var stateAccess: LocalStateAccessorImpl? = nil
    @State private var keysignError: String? = nil
    @State private var pollingInboundMessages = true
    @State private var signature: String = ""

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
                    Text("Generating ECDSA key")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }

            case .KeysignEdDSA:
                HStack {
                    Text("Generating EdDSA key")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }
            case .KeysignFinished:
                VStack {
                    Text("Keysign finished")
                }.onAppear {
                    self.pollingInboundMessages = false
                }
            case .KeysignFailed:
                Text("Sorry keysign failed, you can retry it,error:\(self.keysignError ?? "")")
                    .navigationBarBackButtonHidden(false)
                    .onAppear {
                        self.pollingInboundMessages = false
                    }
            }
        }.task {
            Task(priority: .high) {
                // Create keygen instance, it takes time to generate the preparams
                guard let vault = appState.currentVault else {
                    self.currentStatus = .KeysignFailed
                    return
                }
                self.tssMessenger = TssMessengerImpl(mediatorUrl: self.mediatorURL, sessionID: self.sessionID)
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
                Task {
                    repeat {
                        if Task.isCancelled { return }
                        self.pollInboundMessages()
                        try await Task.sleep(nanoseconds: 1_000_000_000) // Back off 1s
                    } while self.tssService != nil && self.pollingInboundMessages
                }

                self.keysignInProgress = true
                let keysignReq = TssKeysignRequest()
                keysignReq.localPartyKey = vault.localPartyID
                keysignReq.keysignCommitteeKeys = self.keysignCommittee.joined(separator: ",")
                if let msgToSign = self.messsageToSign.data(using: .utf8)?.base64EncodedString() {
                    keysignReq.messageToSign = msgToSign
                }
                do {
                    var resp: TssKeysignResponse?
                    switch self.keysignType {
                    case .ECDSA:
                        keysignReq.pubKey = vault.pubKeyECDSA
                        self.currentStatus = .KeysignECDSA
                        resp = try self.tssService?.keysignECDSA(keysignReq)
                    case .EdDSA:
                        keysignReq.pubKey = vault.pubKeyEdDSA
                        self.currentStatus = .KeysignEdDSA
                        resp = try self.tssService?.keysignEDDSA(keysignReq)
                    }
                    if let resp {
                        self.signature = "R:\(resp.r), S:\(resp.s), RecoveryID:\(resp.recoveryID)"
                    }
                } catch {
                    logger.error("fail to do keysign,error:\(error.localizedDescription)")
                    self.keysignError = error.localizedDescription
                    self.currentStatus = .KeysignFailed
                    return
                }

                self.currentStatus = .KeysignFinished
            }
        }
    }

    private func pollInboundMessages() {
        let urlString = "\(self.mediatorURL)/message/\(self.sessionID)/\(self.localPartyKey)"
        Utils.getRequest(urlString: urlString, completion: { result in
            switch result {
            case .success(let data):
                do {
                    let decoder = JSONDecoder()
                    let msgs = try decoder.decode([Message].self, from: data)

                    for msg in msgs {
                        logger.debug("Got message from: \(msg.from), to: \(msg.to)")
                        try self.tssService?.applyData(msg.body)
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
}

#Preview {
    KeysignView(presentationStack: .constant([]), keysignCommittee: [], mediatorURL: "", sessionID: "session", keysignType: .ECDSA, messsageToSign: "message", localPartyKey: "party id")
}
