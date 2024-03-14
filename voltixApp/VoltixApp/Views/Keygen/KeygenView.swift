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

struct KeygenView: View {
    private let logger = Logger(subsystem: "keygen", category: "tss")
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
    let vault: Vault
    let tssType: TssType  // keygen or reshare
    let keygenCommittee: [String]
    let oldParties: [String]
    let mediatorURL: String
    let sessionID: String
    
    
    @State private var keygenDone = false
    @State private var tssService: TssServiceImpl? = nil
    @State private var tssMessenger: TssMessengerImpl? = nil
    @State private var stateAccess: LocalStateAccessorImpl? = nil
    @State private var keygenError: String? = nil
    @State private var messagePuller = MessagePuller()
    
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

                                        // add the vault to modelcontext
                                    self.context.insert(self.vault)
                                    
                                    Task {
                                            // when user didn't touch it for 5 seconds , automatically goto
                                        try await Task.sleep(for: .seconds(5)) // Back off 5s
                                        self.presentationStack = [CurrentScreen.vaultSelection]
                                    }
                                }.onTapGesture {
                                    self.presentationStack = [CurrentScreen.vaultSelection]
                                }
                                
                            case .KeygenFailed:
                                StatusText(status: "Keygen failed, " + (keygenError ?? ""))
                                    .onAppear {
                                        self.messagePuller.stop()
                                        
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
                guard let tssService = self.tssService else {
                    self.keygenError = "TSS instance is nil"
                    self.currentStatus = .KeygenFailed
                    return
                }
                self.messagePuller.pollMessages(mediatorURL: self.mediatorURL, sessionID: self.sessionID, localPartyKey: vault.localPartyID, tssService: tssService, messageID: nil)
                
                self.currentStatus = .KeygenECDSA
                let keygenReq = TssKeygenRequest()
                keygenReq.localPartyID = vault.localPartyID
                keygenReq.allParties = self.keygenCommittee.joined(separator: ",")
                keygenReq.chainCodeHex = vault.hexChainCode
                logger.info("chaincode:\(vault.hexChainCode)")
                
                let ecdsaResp = try await tssKeygen(service: tssService, req: keygenReq, keyType: .ECDSA)
                self.vault.pubKeyECDSA = ecdsaResp.pubKey
                
                // continue to generate EdDSA Keys
                self.currentStatus = .KeygenEdDSA
                try await Task.sleep(for: .seconds(1)) // Sleep one sec to allow other parties to get in the same step
                
                let eddsaResp = try await tssKeygen(service: tssService, req: keygenReq, keyType: .EdDSA)
                self.vault.pubKeyEdDSA = eddsaResp.pubKey
                
            } catch {
                logger.error("Failed to generate key, error: \(error.localizedDescription)")
                self.currentStatus = .KeygenFailed
                self.keygenError = error.localizedDescription
                return
            }
            self.currentStatus = .KeygenFinished
        }.onDisappear {
            self.messagePuller.stop()
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
                    return try service.keygenEdDSA(req)
            }
        }
        return try await t.value
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
               vault: Vault.example,
               tssType: .Keygen,
               keygenCommittee: [],
               oldParties: [],
               mediatorURL: "",
               sessionID: "")
}
