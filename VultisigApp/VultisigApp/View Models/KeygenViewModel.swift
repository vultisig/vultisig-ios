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
    
    func rightPadHexString(_ hexString: String) -> String {
        guard hexString.allSatisfy({ $0.isHexDigit }) else {
            self.logger.error("Invalid hex string: \(hexString)")
            return hexString
        }
        let paddedLength = 64
        if hexString.count < paddedLength {
            let padding = String(repeating: "0", count: paddedLength - hexString.count)
            return hexString + padding
        }
        return hexString
    }
    func startKeygen(context: ModelContext, defaultChains: [CoinMeta]) async {
        let vaultLibType = self.vault.libType ?? .GG20
        switch(vaultLibType){
        case .GG20:
            switch self.tssType{
            case .Keygen,.Reshare:
                self.status = .KeygenFailed
                self.keygenError = "GG20 keygen not supported for Keygen or Reshare"
            case .Migrate:
                var localUIECDSA: String?
                var localUIEdDSA: String?
                do {
                    // Verify both key shares exist before attempting migration
                    guard let ecdsaShare = self.vault.getKeyshare(pubKey: self.vault.pubKeyECDSA),
                          let eddsaShare = self.vault.getKeyshare(pubKey: self.vault.pubKeyEdDSA) else {
                        throw HelperError.runtimeError("Missing key shares required for migration")
                    }
                    
                    var nsErr: NSError?
                    let ecdsaUIResp = TssGetLocalUIEcdsa(ecdsaShare, &nsErr)
                    if let nsErr {
                        throw HelperError.runtimeError("failed to get local ui ecdsa: \(nsErr.localizedDescription)")
                    }
                    localUIECDSA = rightPadHexString(ecdsaUIResp)
                    let eddsaUIResp = TssGetLocalUIEddsa(eddsaShare, &nsErr)
                    if let nsErr {
                        throw HelperError.runtimeError("failed to get local ui eddsa: \(nsErr.localizedDescription)")
                    }
                    // the local UI sometimes is less than 32 bytes , we need to pad it
                    // since the library expect the number in little-endian , thus we just add 0 to the end of the hex string
                    localUIEdDSA = rightPadHexString(eddsaUIResp)
                    
                } catch {
                    self.logger.error("Migration Failed, fail to get local UI: \(error.localizedDescription)")
                    self.status = .KeygenFailed
                    self.keygenError = error.localizedDescription
                    return
                }
                await startKeygenDKLS(context: context,
                                      defaultChains: defaultChains,
                                      localUIEcdsa: localUIECDSA,
                                      localUIEddsa: localUIEdDSA)
            }
            
        case .DKLS:
            await startKeygenDKLS(context: context, defaultChains: defaultChains)
        }
    }
    
    func startKeygenDKLS(context: ModelContext, defaultChains: [CoinMeta], localUIEcdsa: String? = nil, localUIEddsa: String? = nil) async {
        do{
            let dklsKeygen = DKLSKeygen(vault: self.vault,
                                        tssType: self.tssType,
                                        keygenCommittee: self.keygenCommittee,
                                        vaultOldCommittee: self.vaultOldCommittee,
                                        mediatorURL: self.mediatorURL,
                                        sessionID: self.sessionID,
                                        encryptionKeyHex: self.encryptionKeyHex,
                                        isInitiateDevice: self.isInitiateDevice,
                                        localUI: localUIEcdsa)
            switch self.tssType {
            case .Keygen,.Migrate:
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
                                              isInitiatedDevice: self.isInitiateDevice,
                                              setupMessage: dklsKeygen.getSetupMessage(),
                                              localUI: localUIEddsa)
            switch self.tssType {
            case .Keygen,.Migrate:
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
            if self.tssType == .Migrate {
                // make sure we set the vault's lib type to DKLS , otherwise it won't work
                self.vault.libType = .DKLS
            }
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
    
    func saveFastSignConfig(_ config: FastSignConfig, vault: Vault) {
        keychain.setFastPassword(config.password, pubKeyECDSA: vault.pubKeyECDSA)
        keychain.setFastHint(config.hint, pubKeyECDSA: vault.pubKeyECDSA)
    }

}
