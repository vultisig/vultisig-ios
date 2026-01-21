//
//  KeygenViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftData
import Tss
import WalletCore
import CryptoKit
import BigInt

enum KeygenStatus {
    case CreatingInstance
    case KeygenECDSA
    case ReshareECDSA
    case ReshareEdDSA
    case KeygenEdDSA
    case KeygenFinished
    case KeygenFailed
}

/// Represents a chain to import with its optional custom derivation.
struct ChainImportSetting: Hashable {
    let chain: Chain
    let derivationPath: DerivationPath?

    /// Creates a chain import setting with default derivation
    init(chain: Chain) {
        self.chain = chain
        self.derivationPath = nil
    }

    /// Creates a chain import setting with custom derivation
    init(chain: Chain, derivationPath: DerivationPath) {
        self.chain = chain
        self.derivationPath = derivationPath
    }
}

struct KeyImportInput: Hashable {
    let mnemonic: String
    let chainSettings: [ChainImportSetting]

    /// Gets the derivation type for a specific chain
    func derivationPath(for chain: Chain) -> DerivationPath? {
        chainSettings.first { $0.chain == chain }?.derivationPath
    }

    /// Gets all chains being imported (computed property for backward compatibility)
    var chains: [Chain] {
        chainSettings.map { $0.chain }
    }
}

@MainActor
class KeygenViewModel: ObservableObject {
    private let logger = Logger(subsystem: "keygen-viewmodel", category: "tss")

    /// Maps derivationPath to WalletCore Derivation for each chain.
    /// Add new chains/derivations here to support additional derivation types.
    private let walletCoreDerivations: [Chain: [DerivationPath: Derivation]] = [
        .solana: [
            .phantom: .solanaSolana
            // Add more Solana derivations here in the future, e.g.:
            // .ledger: .someLedgerDerivation
        ]
    ]

    var vault: Vault
    var tssType: TssType // keygen or reshare
    var keygenCommittee: [String]
    var vaultOldCommittee: [String]
    var mediatorURL: String
    var sessionID: String
    var encryptionKeyHex: String
    var oldResharePrefix: String
    var isInitiateDevice: Bool
    var keyImportInput: KeyImportInput?

    @Published var isLinkActive = false
    @Published var keygenError: String = ""
    @Published var status = KeygenStatus.CreatingInstance
    @Published var progress: Float = 0.0

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
                 oldResharePrefix: String,
                 initiateDevice: Bool,
                 keyImportInput: KeyImportInput? = nil
    ) async {
        self.vault = vault
        self.tssType = tssType
        self.keygenCommittee = keygenCommittee
        self.vaultOldCommittee = vaultOldCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.encryptionKeyHex = encryptionKeyHex
        self.oldResharePrefix = oldResharePrefix
        self.isInitiateDevice = initiateDevice
        self.keyImportInput = keyImportInput
        let isEncryptGCM = await FeatureFlagService().isFeatureEnabled(feature: .EncryptGCM)
        messagePuller = MessagePuller(encryptionKeyHex: encryptionKeyHex, pubKey: vault.pubKeyECDSA,
                                      encryptGCM: isEncryptGCM)
    }

    func delaySwitchToMain() {
        Task {
            // when user didn't touch it for 3 seconds , automatically goto home screen
            if !VultisigRelay.IsRelayEnabled {
                try? await Task.sleep(for: .seconds(3)) // Back off 3s
            } else {
                try? await Task.sleep(for: .seconds(2)) // Back off 1s, so we can at least show the done animation
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
    func startKeygen(context: ModelContext) async {
        let vaultLibType = self.vault.libType ?? .GG20
        switch vaultLibType {
        case .GG20:
            switch self.tssType {
            case .Keygen, .Reshare:
                await startKeygenGG20(context: context)
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
                await startKeygenDKLS(context: context, localUIEcdsa: localUIECDSA, localUIEddsa: localUIEdDSA)
            case .KeyImport:
                self.logger.error("it should not get to here")
            }
        case .DKLS:
            await startKeygenDKLS(context: context)
        case .KeyImport:
            do {
                try await startKeyImportKeygen(modelContext: context)
            } catch {
                self.logger.error("Error while generating keygen for Key Import: \(error.localizedDescription)")
                self.status = .KeygenFailed
                self.keygenError = error.localizedDescription
            }
        }
    }

    func startKeyImportKeygen(modelContext: ModelContext) async throws {
        var wallet: HDWallet?

        let steps = 2 + (keyImportInput?.chains.count ?? 0)
        let stepPercentage: Float = 100.0 / Float(steps)

        await addProgress(stepPercentage)
        if self.isInitiateDevice {
            guard let keyImportInput else {
                throw HelperError.runtimeError("Key import keygen should have keyImportInput")
            }

            guard let mnemonicWallet = HDWallet(mnemonic: keyImportInput.mnemonic, passphrase: "") else {
                throw HelperError.runtimeError("Couldn't create HDWallet from mnemonic")
            }

            wallet = mnemonicWallet
        }

        try await startRootKeyImportKeygen(modelContext: modelContext, wallet: wallet)

        guard let chains = keyImportInput?.chains else {
            throw HelperError.runtimeError("KeyImportInput should have at least one chain")
        }

        for chain in chains {
            await addProgress(stepPercentage)
            var chainKey: Data?
            if isInitiateDevice {
                chainKey = getChainKey(for: chain, wallet: wallet)
            }

            let keyshare: DKLSKeyshare
            if chain.isECDSA {
                self.logger.info("Starting DKLS process for chain \(chain.name)")
                keyshare = try await importDklsKey(
                    context: modelContext,
                    ecdsaPrivateKeyHex: chainKey?.hexString,
                    chain: chain
                )
                self.logger.info("Finished DKLS process for chain \(chain.name). Generated pub key: \(keyshare.PubKey)")
            } else {
                var chainSeed: Data?
                if isInitiateDevice {
                    guard let chainKey, let serializedChainSeed = Data.clampThenUniformScalar(from: chainKey) else {
                        throw HelperError.runtimeError("Couldn't transform key to scalar for Schnorr key import for chain \(chain.name)")
                    }
                    chainSeed = serializedChainSeed
                }

                self.logger.info("Starting Schnorr process for chain \(chain.name)")
                keyshare = try await importSchnorrKey(
                    context: modelContext,
                    eddsaPrivateKeyHex: chainSeed?.hexString,
                    chain: chain
                )
                self.logger.info("Finished Schnorr process for chain \(chain.name). Generated pub key: \(keyshare.PubKey)")
            }
            self.vault.keyshares.append(KeyShare(pubkey: keyshare.PubKey, keyshare: keyshare.Keyshare))

            self.vault.chainPublicKeys.append(
                ChainPublicKey(
                    chain: chain,
                    publicKeyHex: keyshare.PubKey,
                    isEddsa: !chain.isECDSA
                )
            )
        }

        await addProgress(stepPercentage)
        self.vault.signers = self.keygenCommittee
        // ensure all party created vault successfully
        let keygenVerify = KeygenVerify(serverAddr: self.mediatorURL,
                                        sessionID: self.sessionID,
                                        localPartyID: self.vault.localPartyID,
                                        keygenCommittee: self.keygenCommittee)
        await keygenVerify.markLocalPartyComplete()
        if self.tssType == .Keygen || !self.vaultOldCommittee.contains(self.vault.localPartyID) {
            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: self.vault)
            modelContext.insert(self.vault)
        }

        try modelContext.save()
        self.status = .KeygenFinished
    }

    func startRootKeyImportKeygen(modelContext: ModelContext, wallet: HDWallet?) async throws {
        self.logger.info("Starting Root Key import process")

        self.logger.info("Starting DKLS process for root key")
        let ecDSAKey = wallet?.getMasterKey(curve: .secp256k1)
        let keyshareECDSA = try await importDklsKey(context: modelContext, ecdsaPrivateKeyHex: ecDSAKey?.data.hexString, chain: nil)
        self.logger.info("Finished DKLS process for root key. Generated pub key: \(keyshareECDSA.PubKey)")

        self.logger.info("Starting Schnorr process for root key")
        let edDSAKey = wallet?.getMasterKey(curve: .ed25519)
        var edDSAKeySerialized: Data?
        if let edDSAKey {
            edDSAKeySerialized = Data.clampThenUniformScalar(from: edDSAKey.data)
        }
        let keyshareEdDSA = try await importSchnorrKey(context: modelContext, eddsaPrivateKeyHex: edDSAKeySerialized?.hexString, chain: nil)
        self.logger.info("Finished Schnorr process for root key. Generated pub key: \(keyshareEdDSA.PubKey)")

        self.vault.pubKeyECDSA = keyshareECDSA.PubKey
        self.vault.pubKeyEdDSA = keyshareEdDSA.PubKey
        self.vault.hexChainCode = keyshareECDSA.chaincode
    }

    /// Gets the chain key using the appropriate derivation based on KeyImportInput settings.
    private func getChainKey(for chain: Chain, wallet: HDWallet?) -> Data? {
        guard let wallet else { return nil }

        // Check if this chain has an alternative derivation configured
        if let derivationPath = keyImportInput?.derivationPath(for: chain),
           let walletCoreDerivation = walletCoreDerivations[chain]?[derivationPath] {
            return wallet.getKeyDerivation(coin: chain.coinType, derivation: walletCoreDerivation).data
        }

        // Use default derivation
        return wallet.getKeyForCoin(coin: chain.coinType).data
    }

    // Import existing ECDSA private key to DKLS vault
    func importDklsKey(context: ModelContext, ecdsaPrivateKeyHex: String?, chain: Chain?) async throws -> DKLSKeyshare {
        do {
            let dklsKeygen = DKLSKeygen(vault: self.vault,
                                        tssType: self.tssType,
                                        keygenCommittee: self.keygenCommittee,
                                        vaultOldCommittee: self.vaultOldCommittee,
                                        mediatorURL: self.mediatorURL,
                                        sessionID: self.sessionID,
                                        encryptionKeyHex: self.encryptionKeyHex,
                                        isInitiateDevice: self.isInitiateDevice,
                                        localUI: ecdsaPrivateKeyHex)
            try await dklsKeygen.DKLSKeygenWithRetry(attempt: 0, additionalHeader: chain?.name)
            guard let keyShare = dklsKeygen.getKeyshare() else {
                throw HelperError.runtimeError("fail to get EdDSA keyshare after import")
            }

            return keyShare
        } catch {
            self.logger.error("Failed to import Ecdsa private key, error: \(error.localizedDescription)")
            throw error
        }
    }
    // Import existing EdDSA private key to DKLS vault
    func importSchnorrKey(context: ModelContext, eddsaPrivateKeyHex: String?, chain: Chain?) async throws -> DKLSKeyshare {
        do {
            let schnorrKeygen = SchnorrKeygen(vault: self.vault,
                                              tssType: self.tssType,
                                              keygenCommittee: self.keygenCommittee,
                                              vaultOldCommittee: self.vaultOldCommittee,
                                              mediatorURL: self.mediatorURL,
                                              sessionID: self.sessionID,
                                              encryptionKeyHex: self.encryptionKeyHex,
                                              isInitiatedDevice: self.isInitiateDevice,
                                              setupMessage: [UInt8](),
                                              localUI: eddsaPrivateKeyHex)
            try await schnorrKeygen.SchnorrKeygenWithRetry(attempt: 0, additionalHeader: chain?.name)
            guard let keyShare = schnorrKeygen.getKeyshare() else {
                throw HelperError.runtimeError("fail to get EdDSA keyshare after import")
            }

            return keyShare
        } catch {
            self.logger.error("Failed to import EdDSA private key, error: \(error.localizedDescription)")
            throw error
        }
    }

    // Create DKLS vault via keygen or reshare
    // This function is also used for private key import , but mostly for import root private keys(both ECDSA and EdDSA)
    func startKeygenDKLS(context: ModelContext, localUIEcdsa: String? = nil, localUIEddsa: String? = nil) async {
        await updateProgress(50)
        do {
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
            case .Keygen, .Migrate:
                self.status = .KeygenECDSA
                try await dklsKeygen.DKLSKeygenWithRetry(attempt: 0)
            case .Reshare:
                self.status = .ReshareECDSA
                try await dklsKeygen.DKLSReshareWithRetry(attempt: 0)
            case .KeyImport:
                self.status = .KeygenECDSA
                try await dklsKeygen.DKLSKeygenWithRetry(attempt: 0)
            }

            await updateProgress(80)

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
            case .Keygen, .Migrate:
                self.status = .KeygenEdDSA
                try await schnorrKeygen.SchnorrKeygenWithRetry(attempt: 0)
            case .Reshare:
                self.status = .ReshareEdDSA
                try await schnorrKeygen.SchnorrReshareWithRetry(attempt: 0)
            case .KeyImport:
                self.status = .KeygenEdDSA
                try await schnorrKeygen.SchnorrKeygenWithRetry(attempt: 0)
            }

            await updateProgress(100)

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

            if self.tssType == .Keygen || !self.vaultOldCommittee.contains(self.vault.localPartyID) {
                VaultDefaultCoinService(context: context)
                    .setDefaultCoinsOnce(vault: self.vault)
                context.insert(self.vault)
            }

            try context.save()
            self.status = .KeygenFinished
        } catch {
            self.logger.error("Failed to generate DKLS key, error: \(error.localizedDescription)")
            self.status = .KeygenFailed
            self.keygenError = error.localizedDescription
            return
        }
    }

    func startKeygenGG20(context: ModelContext) async {
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
                    .setDefaultCoinsOnce(vault: self.vault)
                context.insert(self.vault)
            case .Reshare:
                // if local party is not in the old committee , then he is the new guy , need to add the vault
                // otherwise , they previously have the vault
                if !self.vaultOldCommittee.contains(self.vault.localPartyID) {
                    VaultDefaultCoinService(context: context)
                        .setDefaultCoinsOnce(vault: self.vault)
                    context.insert(self.vault)
                }
            case .Migrate:
                // this should not happen
                self.logger.error("Failed to migration vault")
                self.status = .KeygenFailed
                return
            case .KeyImport:
                // this should not happen
                self.logger.error("Failed to key import vault")
                self.status = .KeygenFailed
                return
            }
            try context.save()
        } catch {
            self.logger.error("Failed to generate key, error: \(error.localizedDescription)")
            self.status = .KeygenFailed
            self.keygenError = error.localizedDescription
            return
        }
    }

    // keygenWithRetry is for creating GG20 vault
    func keygenWithRetry(tssIns: TssServiceImpl, attempt: UInt8) async throws {
        do {
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
            case .Migrate: // GG20 migrate to DKLS should be
                throw HelperError.runtimeError("Migrate not supported yet")
            case .KeyImport: // Vultisig will not support import private key to GG20 vault
                throw HelperError.runtimeError("Key Import not supported yet")
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
                try await keygenWithRetry(tssIns: tssIns, attempt: attempt + 1)
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
                                   localStateAccessor: TssLocalStateAccessorProtocol) async throws -> TssServiceImpl? {
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
                           keyType: KeyType) async throws -> TssKeygenResponse {
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
                            keyType: KeyType) async throws -> TssReshareResponse {
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

    private func updateProgress(_ value: Float) async {
        await MainActor.run {
            self.progress = value
        }
    }

    private func addProgress(_ value: Float) async {
        await MainActor.run {
            self.progress += value
        }
    }
}
