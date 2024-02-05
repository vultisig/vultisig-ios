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
                Text("Keysign finished").onAppear {
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
                self.tssService = TssNewService(self.tssMessenger, self.stateAccess, &err)
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
                keysignReq.localPartyKey = self.localPartyKey
                keysignReq.keysignCommitteeKeys = self.keysignCommittee.joined(separator: ",")
                if let msgToSign = self.messsageToSign.data(using: .utf8)?.base64EncodedString() {
                    keysignReq.messageToSign = msgToSign
                }
                do {
                    switch self.keysignType {
                    case .ECDSA:
                        self.currentStatus = .KeysignECDSA
                        let resp = try tssService?.keysignECDSA(keysignReq)
                    case .EdDSA:
                        self.currentStatus = .KeysignEdDSA
                        let resp = try tssService?.keysignEDDSA(keysignReq)
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
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            return
        }
        
        let req = URLRequest(url: url)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                logger.error("Failed to start session, error: \(error)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response")
                return
            }
            
            if httpResponse.statusCode == 404 {
                // No messages yet
                return
            }
            
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                logger.error("Invalid response code")
                return
            }
            
            guard let data = data else {
                logger.error("No participants available yet")
                return
            }
            
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
        }.resume()
    }
}

#Preview {
    KeysignView(presentationStack: .constant([]), keysignCommittee: [], mediatorURL: "", sessionID: "session", keysignType: .ECDSA, messsageToSign: "message", localPartyKey: "party id")
}
