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
        GeometryReader { geometry in
            ScrollView {
                VStack {
                    Spacer()
                    VStack(alignment: .center) {
                        switch self.currentStatus {
                        case .CreatingInstance:
                            StatusText(status: "PREPARING VAULT...")
                        case .KeygenECDSA:
                            StatusText(status: "GENERATING ECDSA KEY")
                        case .KeygenEdDSA:
                            StatusText(status: "GENERATING EdDSA KEY")
                        case .KeygenFinished:
                            Text("DONE").onAppear {
                                if let stateAccess {
                                    for item in stateAccess.keyshares {
                                        logger.info("keyshare:\(item.pubkey)")
                                    }
                                    self.vault.keyshares = stateAccess.keyshares
                                }
                                self.vault.name = self.vaultName
                                self.vault.localPartyID = self.localPartyKey
                                // add the vault to modelcontext
                                self.context.insert(self.vault)
                                self.pollingInboundMessages = false
                                Task {
                                    // when user didn't touch it for 5 seconds , automatically goto
                                    try await Task.sleep(nanoseconds: 5_000_000_000) // Back off 5s
                                    self.presentationStack = [CurrentScreen.vaultSelection]
                                }
                            }.onTapGesture {
                                self.presentationStack = [CurrentScreen.vaultSelection]
                            }
                            
                        case .KeygenFailed:
                            StatusText(status: "Failed KeyGen Retry")
                                .onAppear {
                                    self.pollingInboundMessages = false
                                }.navigationBarBackButtonHidden(false)
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height * 0.8)
                    Spacer()
                    WifiBar()
                }
            }
        }
        .navigationBarBackButtonHidden()
        .task {
            do {
                self.vault.signers.append(contentsOf: self.keygenCommittee)
                // Create keygen instance, it takes time to generate the preparams
                let messengerImp = TssMessengerImpl(mediatorUrl: self.mediatorURL, sessionID: self.sessionID, messageID: nil)
                let stateAccessorImp = LocalStateAccessorImpl(vault: self.vault)
                self.tssMessenger = messengerImp
                self.stateAccess = stateAccessorImp
                self.tssService = try await self.createTssInstance(messenger: messengerImp,
                                                                   localStateAccessor: stateAccessorImp)
                
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
                guard let tssService = self.tssService else {
                    self.keygenError = "TSS instance is nil"
                    self.currentStatus = .KeygenFailed
                    return
                }
                
                let ecdsaResp = try await tssKeygen(service: tssService, req: keygenReq, keyType: .ECDSA)
                self.pubKeyECDSA = ecdsaResp.pubKey
                self.vault.pubKeyECDSA = ecdsaResp.pubKey
                
                self.currentStatus = .KeygenEdDSA
                self.keygenInProgressEDDSA = true
                try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep one sec to allow other parties to get in the same step
                
                let eddsaResp = try await tssKeygen(service: tssService, req: keygenReq, keyType: .EdDSA)
                self.pubKeyEdDSA = eddsaResp.pubKey
                self.vault.pubKeyEdDSA = eddsaResp.pubKey
                
            } catch {
                logger.error("Failed to generate key, error: \(error.localizedDescription)")
                self.currentStatus = .KeygenFailed
                self.keygenError = error.localizedDescription
                return
            }
            self.currentStatus = .KeygenFinished
        }
    }
    
    private func createTssInstance(messenger: TssMessengerProtocol,
                                   localStateAccessor: TssLocalStateAccessorProtocol) async throws -> TssServiceImpl?
    {
        let t = Task.detached(priority: .high) {
            var err: NSError?
            let service = TssNewService(self.tssMessenger, self.stateAccess, true, &err)
            if let err {
                throw err
            }
            return service
        }
        return try await t.value
    }
    
    private func tssKeygen(service: TssServiceImpl,
                           req: TssKeygenRequest,
                           keyType: KeyType) async throws -> TssKeygenResponse
    {
        let t = Task.detached(priority: .high) {
            switch keyType {
            case .ECDSA:
                return try service.keygenECDSA(req)
            case .EdDSA:
                return try service.keygenEDDSA(req)
            }
        }
        return try await t.value
    }
    
    private func pollInboundMessages() {
        let urlString = "\(self.mediatorURL)/message/\(self.sessionID)/\(self.localPartyKey)"
        Utils.getRequest(urlString: urlString, headers: [String: String](), completion: { result in
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

private struct StatusText: View {
    let status: String
    var body: some View {
        HStack {
            Text(self.status)
                .fontWeight(/*@START_MENU_TOKEN@*/ .bold/*@END_MENU_TOKEN@*/)
                .multilineTextAlignment(.center)
            ProgressView()
                .progressViewStyle(.circular)
                .padding(2)
        }
    }
}

#Preview("keygen") {
    KeygenView(presentationStack: .constant([]),
               keygenCommittee: [],
               mediatorURL: "",
               sessionID: "",
               localPartyKey: "",
               vaultName: "Vault #1")
}
