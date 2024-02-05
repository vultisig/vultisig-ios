//
//  Keygen.swift
//  VoltixApp
//

import CryptoKit
import Foundation
import Mediator
import OSLog
import SwiftData
import SwiftUI
import Tss

private let logger = Logger(subsystem: "keygen", category: "tss")
struct KeygenView: View {
    @Environment(\.modelContext) private var context
    enum KeygenStatus {
        case CreatingInstance
        case KeygenECDSA
        case KeygenEdDSA
        case KeygenFinished
        case KeygenFailed
    }
    
    @State private var currentStatus = KeygenStatus.CreatingInstance
    @Binding var presentationStack: [CurrentScreen]
    let keygenCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let localPartyKey: String
    @State private var keygenInProgressECDSA = false
    @State private var pubKeyECDSA: String? = nil
    @State private var keygenInProgressEDDSA = false
    @State private var pubKeyEdDSA: String? = nil
    @State private var keygenDone = false
    @State private var tssService: TssServiceImpl? = nil
    @State private var failToCreateTssInstance = false
    @State private var tssMessenger: TssMessengerImpl? = nil
    @State private var stateAccess: LocalStateAccessorImpl? = nil
    @State private var keygenError: String? = nil
    @State private var vault = Vault(name: "new vault")
    @State var vaultName: String
    @State var pollingInboundMessages = true
    
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
            case .KeygenECDSA:
                HStack {
                    if self.keygenInProgressECDSA {
                        Text("Generating ECDSA key")
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.blue)
                            .padding(2)
                    }
                    if self.pubKeyECDSA != nil {
                        Text("ECDSA pubkey:\(self.pubKeyECDSA ?? "")")
                        Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/ .blue/*@END_MENU_TOKEN@*/)
                    }
                }
            case .KeygenEdDSA:
                HStack {
                    if self.keygenInProgressEDDSA {
                        Text("Generating EdDSA key")
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.blue)
                            .padding(2)
                    }
                    if self.pubKeyEdDSA != nil {
                        Text("EdDSA pubkey:\(self.pubKeyEdDSA ?? "")")
                        Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/ .blue/*@END_MENU_TOKEN@*/)
                    }
                }
            case .KeygenFinished:
                FinishedTSSKeygenView(presentationStack: self.$presentationStack, vault: self.vault).onAppear {
                    if let stateAccess {
                        for item in stateAccess.keyshares {
                            logger.info("keyshare:\(item.pubkey)")
                        }
                        self.vault.keyshares = stateAccess.keyshares
                    }
                    self.vault.name = self.vaultName
                    // add the vault to modelcontext
                    self.context.insert(self.vault)
                    self.pollingInboundMessages = false
                }
            case .KeygenFailed:
                Text("Sorry keygen failed, you can retry it,error:\(self.keygenError ?? "")")
                    .navigationBarBackButtonHidden(false)
                    .onAppear {
                        self.pollingInboundMessages = false
                    }
            }
        }.task {
            Task.detached(priority: .high) {
                self.vault.signers.append(contentsOf: self.keygenCommittee)
                // Create keygen instance, it takes time to generate the preparams
                self.tssMessenger = TssMessengerImpl(mediatorUrl: self.mediatorURL, sessionID: self.sessionID)
                self.stateAccess = LocalStateAccessorImpl(vault: self.vault)
                var err: NSError?
                self.tssService = TssNewService(self.tssMessenger, self.stateAccess, &err)
                if let err {
                    logger.error("Failed to create TSS instance, error: \(err.localizedDescription)")
                    self.failToCreateTssInstance = true
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
                
                self.currentStatus = .KeygenECDSA
                self.keygenInProgressECDSA = true
                let keygenReq = TssKeygenRequest()
                keygenReq.localPartyID = self.localPartyKey
                keygenReq.allParties = self.keygenCommittee.joined(separator: ",")
                
                do {
                    if let tssService = self.tssService {
                        let ecdsaResp = try tssService.keygenECDSA(keygenReq)
                        self.pubKeyECDSA = ecdsaResp.pubKey
                        self.vault.pubKeyECDSA = ecdsaResp.pubKey
                    }
                } catch {
                    logger.error("Failed to create ECDSA key, error: \(error.localizedDescription)")
                    self.currentStatus = .KeygenFailed
                    self.keygenError = error.localizedDescription
                    return
                }
                
                self.currentStatus = .KeygenEdDSA
                self.keygenInProgressEDDSA = true
                try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep one sec to allow other parties to get in the same step
                
                do {
                    if let tssService = self.tssService {
                        let eddsaResp = try tssService.keygenEDDSA(keygenReq)
                        self.pubKeyEdDSA = eddsaResp.pubKey
                        self.vault.pubKeyEdDSA = eddsaResp.pubKey
                    }
                } catch {
                    logger.error("Failed to create EdDSA key, error: \(error.localizedDescription)")
                    self.currentStatus = .KeygenFailed
                    self.keygenError = error.localizedDescription
                    return
                }
                
                self.currentStatus = .KeygenFinished
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

#Preview("keygen") {
    KeygenView(presentationStack: .constant([]), keygenCommittee: [], mediatorURL: "", sessionID: "", localPartyKey: "", vaultName: "Vault #1")
}
