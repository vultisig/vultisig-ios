//
//  KeygenViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftData
import Tss

enum KeygenStatus {
    case CreatingInstance
    case KeygenECDSA
    case ReshareECDSA
    case ReshareEdDSA
    case KeygenEdDSA
    case KeygenFinished
    case KeygenFailed
}

@MainActor
class KeygenViewModel: ObservableObject {
    private let logger = Logger(subsystem: "keygen-viewmodel", category: "tss")
    
    var vault: Vault
    var tssType: TssType // keygen or reshare
    var keygenCommittee: [String]
    var vaultOldCommittee: [String]
    var mediatorURL: String
    var sessionID: String
    var encryptionKeyHex: String
    var oldResharePrefix: String
    var isInitiateDevice: Bool
    
    @Published var isLinkActive = false
    @Published var keygenError: String = ""
    @Published var status = KeygenStatus.CreatingInstance
    
    private var tssService: TssServiceImpl? = nil
    private var tssMessenger: TssMessengerImpl? = nil
    private var stateAccess: LocalStateAccessorImpl? = nil
    private var messagePuller: MessagePuller? = nil
    
    private let keychain = DefaultKeychainService.shared
    
    init() {
        self.vault = Vault(name: "Main Vault")
        self.tssType = .Keygen
        self.keygenCommittee = []
        self.vaultOldCommittee = []
        self.mediatorURL = ""
        self.sessionID = ""
        self.encryptionKeyHex = ""
        self.oldResharePrefix = ""
        self.isInitiateDevice = false
    }
    
    func setData(vault: Vault,
                 tssType: TssType,
                 keygenCommittee: [String],
                 vaultOldCommittee: [String],
                 mediatorURL: String,
                 sessionID: String,
                 encryptionKeyHex: String,
                 oldResharePrefix:String,
                 initiateDevice: Bool) async {
        self.vault = vault
        self.tssType = tssType
        self.keygenCommittee = keygenCommittee
        self.vaultOldCommittee = vaultOldCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.encryptionKeyHex = encryptionKeyHex
        self.oldResharePrefix = oldResharePrefix
        self.isInitiateDevice = initiateDevice
        let isEncryptGCM = await FeatureFlagService().isFeatureEnabled(feature: .EncryptGCM)
        messagePuller = MessagePuller(encryptionKeyHex: encryptionKeyHex,pubKey: vault.pubKeyECDSA,
                                      encryptGCM: isEncryptGCM)
    }
    
    func delaySwitchToMain() {
        Task {
            // when user didn't touch it for 3 seconds , automatically goto home screen
            if !VultisigRelay.IsRelayEnabled {
                try await Task.sleep(for: .seconds(3)) // Back off 3s
            } else {
                try await Task.sleep(for: .seconds(2)) // Back off 1s, so we can at least show the done animation
            }
            self.isLinkActive = true
        }
    }
    
    func startKeygen(context: ModelContext, defaultChains: [CoinMeta]) async {
        switch(self.vault.libType){
        case .GG20:
            await startKeygenGG20(context: context, defaultChains: defaultChains)
        case .DKLS:
            await startKeygenDKLS(context: context, defaultChains: defaultChains)
        default:
            print("invalid vault lib type")
            return
        }
    }
    
    func startKeygenDKLS(context: ModelContext, defaultChains: [CoinMeta]) async {
        do{
            let dklsKeygen = DKLSKeygen(vault: self.vault,
                                        tssType: self.tssType,
                                        keygenCommittee: self.keygenCommittee,
                                        vaultOldCommittee: self.vaultOldCommittee,
                                        mediatorURL: self.mediatorURL,
                                        sessionID: self.sessionID,
                                        encryptionKeyHex: self.encryptionKeyHex,
                                        oldResharePrefix: self.oldResharePrefix,
                                        isInitiateDevice: self.isInitiateDevice)
            switch self.tssType {
            case .Keygen:
                self.status = .KeygenECDSA
                try await dklsKeygen.DKLSKeygenWithRetry(attempt: 0)
            case .Reshare:
                self.status = .ReshareECDSA
                try await dklsKeygen.DKLSReshareWithRetry(attempt: 0)
            }
            
            
            let schnorrKeygen = SchnorrKeygen(vault: self.vault,
                                              tssType: self.tssType,
                                              keygenCommittee: self.keygenCommittee,
                                              vaultOldCommittee: self.vaultOldCommittee,
                                              mediatorURL: self.mediatorURL,
                                              sessionID: self.sessionID,
                                              encryptionKeyHex: self.encryptionKeyHex,
                                              oldResharePrefix: self.oldResharePrefix,
                                              isInitiatedDevice: self.isInitiateDevice,
                                              setupMessage: dklsKeygen.getSetupMessage())
            switch self.tssType {
            case .Keygen:
                self.status = .KeygenEdDSA
                try await schnorrKeygen.SchnorrKeygenWithRetry(attempt: 0)
            case .Reshare:
                self.status = .ReshareEdDSA
                try await schnorrKeygen.SchnorrReshareWithRetry(attempt: 0)
            }
            
            self.vault.signers = self.keygenCommittee
            let keyshareECDSA = dklsKeygen.getKeyshare()
            let keyshareEdDSA = schnorrKeygen.getKeyshare()
            guard let keyshareECDSA else {
                throw HelperError.runtimeError("fail to get ECDSA keyshare")
            }
            guard let keyshareEdDSA else {
                throw HelperError.runtimeError("fail to get EdDSA keyshare")
            }
            
            // ensure all party created vault successfully
            let keygenVerify = KeygenVerify(serverAddr: self.mediatorURL,
                                            sessionID: self.sessionID,
                                            localPartyID: self.vault.localPartyID,
                                            keygenCommittee: self.keygenCommittee)
            await keygenVerify.markLocalPartyComplete()
            let allFinished = await keygenVerify.checkCompletedParties()
            if !allFinished {
                throw HelperError.runtimeError("partial vault created, not all parties finished successfully")
            }
            
            self.vault.pubKeyECDSA = keyshareECDSA.PubKey
            self.vault.pubKeyEdDSA = keyshareEdDSA.PubKey
            self.vault.hexChainCode = keyshareECDSA.chaincode
            self.vault.keyshares = [KeyShare(pubkey: keyshareECDSA.PubKey, keyshare: keyshareECDSA.Keyshare),
                                    KeyShare(pubkey: keyshareEdDSA.PubKey, keyshare: keyshareEdDSA.Keyshare)]
            
            if self.tssType == .Keygen || !self.vaultOldCommittee.contains(self.vault.localPartyID){
                VaultDefaultCoinService(context: context)
                    .setDefaultCoinsOnce(vault: self.vault, defaultChains: defaultChains)
                context.insert(self.vault)
            }
            try context.save()
            self.status = .KeygenFinished
        } catch{
            self.logger.error("Failed to generate DKLS key, error: \(error.localizedDescription)")
            self.status = .KeygenFailed
            self.keygenError = error.localizedDescription
            return
        }
    }
    
    func startKeygenGG20(context: ModelContext, defaultChains: [CoinMeta]) async {
        defer {
            self.messagePuller?.stop()
        }
        do {
            let isEncryptGCM = await FeatureFlagService().isFeatureEnabled(feature: .EncryptGCM)
            // Create keygen instance, it takes time to generate the preparams
            let messengerImp = TssMessengerImpl(
                mediatorUrl: self.mediatorURL,
                sessionID: self.sessionID,
                messageID: nil,
                encryptionKeyHex: encryptionKeyHex,
                vaultPubKey: "",
                isKeygen: true,
                encryptGCM: isEncryptGCM
            )
            let stateAccessorImp = LocalStateAccessorImpl(vault: self.vault)
            self.tssMessenger = messengerImp
            self.stateAccess = stateAccessorImp
            self.tssService = try await self.createTssInstance(messenger: messengerImp,
                                                               localStateAccessor: stateAccessorImp)
            guard let tssService = self.tssService else {
                throw HelperError.runtimeError("TSS instance is nil")
            }
            try await keygenWithRetry(tssIns: tssService, attempt: 1)
            // if keygenWithRetry return without exception, it means keygen finished successfully
            self.status = .KeygenFinished
            
            self.vault.signers = self.keygenCommittee
            // save the vault
            if let stateAccess {
                self.vault.keyshares = stateAccess.keyshares
            }
            switch self.tssType {
            case .Keygen:
                // make sure the newly created vault has default coins
                VaultDefaultCoinService(context: context)
                    .setDefaultCoinsOnce(vault: self.vault, defaultChains: defaultChains)
                context.insert(self.vault)
            case .Reshare:
                // if local party is not in the old committee , then he is the new guy , need to add the vault
                // otherwise , they previously have the vault
                if !self.vaultOldCommittee.contains(self.vault.localPartyID) {
                    VaultDefaultCoinService(context: context)
                        .setDefaultCoinsOnce(vault: self.vault, defaultChains: defaultChains)
                    context.insert(self.vault)
                }
            }
            try context.save()
        } catch {
            self.logger.error("Failed to generate key, error: \(error.localizedDescription)")
            self.status = .KeygenFailed
            self.keygenError = error.localizedDescription
            return
        }
    }
    
    func keygenWithRetry(tssIns: TssServiceImpl,attempt: UInt8) async throws {
        do{
            self.messagePuller?.pollMessages(mediatorURL: self.mediatorURL,
                                             sessionID: self.sessionID,
                                             localPartyKey: self.vault.localPartyID,
                                             tssService: tssIns,
                                             messageID: nil)
            switch self.tssType {
            case .Keygen:
                self.status = .KeygenECDSA
                let keygenReq = TssKeygenRequest()
                keygenReq.localPartyID = self.vault.localPartyID
                keygenReq.allParties = self.keygenCommittee.joined(separator: ",")
                keygenReq.chainCodeHex = self.vault.hexChainCode
                self.logger.info("chaincode:\(self.vault.hexChainCode)")
                
                let ecdsaResp = try await tssKeygen(service: tssIns, req: keygenReq, keyType: .ECDSA)
                self.vault.pubKeyECDSA = ecdsaResp.pubKey
                
                // continue to generate EdDSA Keys
                self.status = .KeygenEdDSA
                try await Task.sleep(for: .seconds(1)) // Sleep one sec to allow other parties to get in the same step
                
                let eddsaResp = try await tssKeygen(service: tssIns, req: keygenReq, keyType: .EdDSA)
                self.vault.pubKeyEdDSA = eddsaResp.pubKey
            case .Reshare:
                self.status = .ReshareECDSA
                let reshareReq = TssReshareRequest()
                reshareReq.localPartyID = self.vault.localPartyID
                reshareReq.pubKey = self.vault.pubKeyECDSA
                reshareReq.oldParties = self.vaultOldCommittee.joined(separator: ",")
                reshareReq.newParties = self.keygenCommittee.joined(separator: ",")
                reshareReq.resharePrefix = self.vault.resharePrefix ?? self.oldResharePrefix
                reshareReq.chainCodeHex = self.vault.hexChainCode
                self.logger.info("chaincode:\(self.vault.hexChainCode)")
                let ecdsaResp = try await tssReshare(service: tssIns, req: reshareReq, keyType: .ECDSA)
                // continue to generate EdDSA Keys
                self.status = .ReshareEdDSA
                try await Task.sleep(for: .seconds(1)) // Sleep one sec to allow other parties to get in the same step
                reshareReq.pubKey = self.vault.pubKeyEdDSA
                reshareReq.newResharePrefix = ecdsaResp.resharePrefix
                let eddsaResp = try await tssReshare(service: tssIns, req: reshareReq, keyType: .EdDSA)
                self.vault.pubKeyEdDSA = eddsaResp.pubKey
                self.vault.pubKeyECDSA = ecdsaResp.pubKey
                self.vault.resharePrefix = ecdsaResp.resharePrefix
            }
            // start an additional step to make sure all parties involved in the keygen committee complete successfully
            // avoid to create a partial vault, meaning some parties finished create the vault successfully, and one still in failed state
            let keygenVerify = KeygenVerify(serverAddr: self.mediatorURL,
                                            sessionID: self.sessionID,
                                            localPartyID: self.vault.localPartyID,
                                            keygenCommittee: self.keygenCommittee)
            await keygenVerify.markLocalPartyComplete()
            let allFinished = await keygenVerify.checkCompletedParties()
            if !allFinished {
                throw HelperError.runtimeError("partial vault created, not all parties finished successfully")
            }
            
        } catch {
            self.messagePuller?.stop()
            self.logger.error("Failed to generate key, error: \(error.localizedDescription)")
            if attempt < 3 { // let's retry
                logger.info("keygen/reshare retry, attemp: \(attempt)")
                try await keygenWithRetry(tssIns: tssIns,  attempt: attempt + 1)
            } else {
                throw error
            }
        }
        
    }
    
    func saveFastSignConfig(_ config: FastSignConfig, vault: Vault) {
        keychain.setFastPassword(config.password, pubKeyECDSA: vault.pubKeyECDSA)
        keychain.setFastHint(config.hint, pubKeyECDSA: vault.pubKeyECDSA)
    }
    
    private func createTssInstance(messenger: TssMessengerProtocol,
                                   localStateAccessor: TssLocalStateAccessorProtocol) async throws -> TssServiceImpl?
    {
        let t = Task.detached(priority: .high) {
            var err: NSError?
            let service = await TssNewService(self.tssMessenger, self.stateAccess, true, &err)
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
    
    private func tssReshare(service: TssServiceImpl,
                            req: TssReshareRequest,
                            keyType: KeyType) async throws -> TssReshareResponse
    {
        let t = Task.detached(priority: .high) {
            switch keyType {
            case .ECDSA:
                return try service.reshareECDSA(req)
            case .EdDSA:
                return try service.resharingEdDSA(req)
            }
        }
        return try await t.value
    }
    
}
