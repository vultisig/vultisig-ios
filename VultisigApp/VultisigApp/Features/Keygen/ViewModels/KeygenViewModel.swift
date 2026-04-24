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
    case KeygenMLDSA
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
    var singleKeygenType: SingleKeygenType?

    @Published var isLinkActive = false
    @Published var keygenError: String = ""
    @Published var status = KeygenStatus.CreatingInstance
    @Published var progress: Float = 0.0
    @Published var showDuplicateVaultAlert = false
    @Published var duplicateVaultName: String = ""
    @Published var didCancelDuplicateVault = false
    @Published var keygenConnected = false

    private var duplicateVaultContinuation: CheckedContinuation<Bool, Never>?
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
                 keyImportInput: KeyImportInput? = nil,
                 singleKeygenType: SingleKeygenType? = nil
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
        self.singleKeygenType = singleKeygenType
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

    func confirmDuplicateVaultIfNeeded(context: ModelContext) async -> Bool {
        let pubKey = self.vault.pubKeyECDSA
        guard !pubKey.isEmpty else { return true }

        let descriptor = FetchDescriptor<Vault>()
        guard let existingVaults = try? context.fetch(descriptor) else { return true }
        guard let existing = existingVaults.first(where: { $0.pubKeyECDSA == pubKey }) else {
            return true
        }

        self.duplicateVaultName = existing.name
        self.showDuplicateVaultAlert = true

        return await withCheckedContinuation { continuation in
            self.duplicateVaultContinuation = continuation
        }
    }

    func resolveDuplicateVault(shouldReplace: Bool) {
        showDuplicateVaultAlert = false
        duplicateVaultContinuation?.resume(returning: shouldReplace)
        duplicateVaultContinuation = nil
    }

    func startKeygen(context: ModelContext) async {
        self.keygenConnected = true

        if self.tssType == .SingleKeygen {
            await startSingleKeygen(context: context)
            return
        }

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
            case .SingleKeygen:
                self.logger.error("SingleKeygen should not reach GG20 path")
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

    func startSingleKeygen(context: ModelContext) async {
        do {
            guard let singleKeygenType else {
                throw HelperError.runtimeError("singleKeygenType is not set")
            }
            switch singleKeygenType {
            case .MLDSA:
                self.status = .KeygenMLDSA
                let dilithiumKeygen = DilithiumKeygen(
                    vault: self.vault,
                    tssType: self.tssType,
                    keygenCommittee: self.keygenCommittee,
                    mediatorURL: self.mediatorURL,
                    sessionID: self.sessionID,
                    encryptionKeyHex: self.encryptionKeyHex,
                    isInitiateDevice: self.isInitiateDevice,
                    setupMessage: [UInt8]()
                )
                try await dilithiumKeygen.DilithiumKeygenWithRetry(attempt: 0)

                guard let keyshare = dilithiumKeygen.getKeyshare() else {
                    throw HelperError.runtimeError("fail to get MLDSA keyshare")
                }

                let keygenVerify = KeygenVerify(
                    serverAddr: self.mediatorURL,
                    sessionID: self.sessionID,
                    localPartyID: self.vault.localPartyID,
                    keygenCommittee: self.keygenCommittee
                )
                await keygenVerify.markLocalPartyComplete()
                let allFinished = await keygenVerify.checkCompletedParties()
                if !allFinished {
                    throw HelperError.runtimeError("not all parties finished MLDSA keygen successfully")
                }

                self.vault.publicKeyMLDSA44 = keyshare.PubKey
                self.vault.keyshares.append(
                    KeyShare(pubkey: keyshare.PubKey, keyshare: keyshare.Keyshare, keyId: keyshare.keyId)
                )
                self.vault.isBackedUp = false
            }

            try context.save()
            self.status = .KeygenFinished
        } catch {
            self.logger.error("Failed to generate MLDSA key, error: \(error.localizedDescription)")
            self.status = .KeygenFailed
            self.keygenError = error.localizedDescription
        }
    }

    func startKeyImportKeygen(modelContext: ModelContext) async throws {
        let isTssBatchEnabled = await FeatureFlagService().isFeatureEnabled(feature: .TssBatch)
        let useParallelPath = isTssBatchEnabled
        self.logger.info("KeyImport flow starting: execution=\(useParallelPath ? "parallel" : "sequential"), tssBatchEnabled=\(isTssBatchEnabled)")

        var wallet: HDWallet?

        let steps = 2 + (keyImportInput?.chains.count ?? 0)
        let stepPercentage: Float = 100.0 / Float(steps)

        self.status = .KeygenECDSA
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

        guard let chains = keyImportInput?.chains, !chains.isEmpty else {
            throw HelperError.runtimeError("KeyImportInput should have at least one chain")
        }

        let ecdsaHex = wallet?.getMasterKey(curve: .secp256k1).data.hexString
        var eddsaHex: String?
        if let edDSAKey = wallet?.getMasterKey(curve: .ed25519) {
            eddsaHex = Data.clampThenUniformScalar(from: edDSAKey.data)?.hexString
        }
        let rootDkls = makeDklsKeygen(localUI: ecdsaHex)
        let rootSchnorr = makeSchnorrKeygen(localUI: eddsaHex)

        // Batch key import uses the same relay exchange namespaces as batch keygen
        // (p-ecdsa, p-eddsa, p-{chain}) because the server's /batch/import handler
        // polls those channels. Root DKLS setup goes to the default namespace;
        // root Schnorr setup has its own eddsa_key_import namespace to avoid collision.
        let rootEcdsaRouting: KeygenRouting = useParallelPath
            ? KeygenRouting.from(exchangeMessageId: KeygenMessageId.rootECDSA)
            : .default
        let rootEddsaRouting: KeygenRouting = useParallelPath
            ? KeygenRouting.from(
                setupMessageId: KeygenMessageId.rootEdDSAKeyImport,
                exchangeMessageId: KeygenMessageId.rootEdDSA
              )
            : .default

        let chainJobs = try buildChainImportJobs(chains: chains, wallet: wallet, useParallelPath: useParallelPath)

        // Phase 1 (parallel path only): upload every setup message to the relay
        // before any protocol starts TSS exchange. The server's /batch/import
        // endpoint downloads all setup messages serially with a 1-minute timeout
        // each before launching any keygen goroutine; if per-chain setups arrive
        // only after root keygen exchange starts, the server times out and both
        // sides hang on mismatched relay channels.
        if useParallelPath {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await rootDkls.prepareKeyImportSetup(routing: rootEcdsaRouting)
                }
                group.addTask {
                    try await rootSchnorr.prepareKeyImportSetup(routing: rootEddsaRouting)
                }
                for job in chainJobs {
                    group.addTask {
                        try await Self.prepareChainImportJob(job)
                    }
                }
                try await group.waitForAll()
            }
        }

        try await runRootKeyImportKeygen(
            dklsKeygen: rootDkls,
            schnorrKeygen: rootSchnorr,
            useParallelPath: useParallelPath,
            ecdsaRouting: rootEcdsaRouting,
            eddsaRouting: rootEddsaRouting
        )

        var seenPubKeys: Set<String> = [self.vault.pubKeyECDSA, self.vault.pubKeyEdDSA]

        let chainResults: [KeyImportChainResult]
        if useParallelPath {
            chainResults = try await withThrowingTaskGroup(of: (Int, KeyImportChainResult).self) { group in
                for (index, job) in chainJobs.enumerated() {
                    group.addTask {
                        let result = try await Self.executeChainImportJob(job)
                        return (index, result)
                    }
                }
                var collected: [(Int, KeyImportChainResult)] = []
                for try await pair in group {
                    collected.append(pair)
                    await addProgress(stepPercentage)
                }
                return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
        } else {
            var collected: [KeyImportChainResult] = []
            for job in chainJobs {
                let result = try await Self.executeChainImportJob(job)
                await addProgress(stepPercentage)
                collected.append(result)
            }
            chainResults = collected
        }

        for result in chainResults {
            if seenPubKeys.insert(result.keyshare.PubKey).inserted {
                self.vault.keyshares.append(
                    KeyShare(pubkey: result.keyshare.PubKey, keyshare: result.keyshare.Keyshare)
                )
            }
            self.vault.chainPublicKeys.append(
                ChainPublicKey(
                    chain: result.chain,
                    publicKeyHex: result.keyshare.PubKey,
                    isEddsa: result.isEddsa
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
        let needsInsert = self.tssType == .Keygen ||
            !self.vaultOldCommittee.contains(self.vault.localPartyID)

        if needsInsert {
            let shouldProceed = await confirmDuplicateVaultIfNeeded(context: modelContext)
            if !shouldProceed {
                self.didCancelDuplicateVault = true
                return
            }
            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: self.vault)
            modelContext.insert(self.vault)
        }

        try modelContext.save()
        self.status = .KeygenFinished
    }

    private func runRootKeyImportKeygen(
        dklsKeygen: DKLSKeygen,
        schnorrKeygen: SchnorrKeygen,
        useParallelPath: Bool,
        ecdsaRouting: KeygenRouting,
        eddsaRouting: KeygenRouting
    ) async throws {
        self.logger.info("Starting Root Key import process")

        if useParallelPath {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await dklsKeygen.DKLSKeygenWithRetry(attempt: 0, routing: ecdsaRouting)
                }
                group.addTask {
                    try await schnorrKeygen.SchnorrKeygenWithRetry(attempt: 0, routing: eddsaRouting)
                }
                try await group.waitForAll()
            }
        } else {
            try await dklsKeygen.DKLSKeygenWithRetry(attempt: 0, routing: ecdsaRouting)
            try await schnorrKeygen.SchnorrKeygenWithRetry(attempt: 0, routing: eddsaRouting)
        }

        guard let rootEcdsa = dklsKeygen.getKeyshare() else {
            throw HelperError.runtimeError("fail to get ECDSA keyshare after root import")
        }
        guard let rootEddsa = schnorrKeygen.getKeyshare() else {
            throw HelperError.runtimeError("fail to get EdDSA keyshare after root import")
        }

        self.logger.info("Finished root key import. ECDSA pub: \(rootEcdsa.PubKey), EdDSA pub: \(rootEddsa.PubKey)")

        self.vault.pubKeyECDSA = rootEcdsa.PubKey
        self.vault.pubKeyEdDSA = rootEddsa.PubKey
        self.vault.hexChainCode = rootEcdsa.chaincode
        self.vault.keyshares.append(KeyShare(pubkey: rootEcdsa.PubKey, keyshare: rootEcdsa.Keyshare))
        self.vault.keyshares.append(KeyShare(pubkey: rootEddsa.PubKey, keyshare: rootEddsa.Keyshare))
    }

    private func buildChainImportJobs(chains: [Chain], wallet: HDWallet?, useParallelPath: Bool) throws -> [KeyImportChainJob] {
        var jobs: [KeyImportChainJob] = []
        for chain in chains {
            var chainKey: Data?
            if isInitiateDevice {
                chainKey = getChainKey(for: chain, wallet: wallet)
            }

            // Parallel path: setup goes to chain.name, exchange to p-{chain.name}
            // (matching the server's /batch/import relay channels). Sequential path
            // keeps the legacy shared exchange namespace — only setup is chain-scoped.
            let routing: KeygenRouting = useParallelPath
                ? KeygenRouting.from(setupMessageId: chain.name, exchangeMessageId: "p-\(chain.name)")
                : KeygenRouting.from(setupMessageId: chain.name)

            if chain.isECDSA {
                let dkls = makeDklsKeygen(localUI: chainKey?.hexString)
                jobs.append(KeyImportChainJob(chain: chain, isEddsa: false, routing: routing, dkls: dkls, schnorr: nil))
            } else {
                var chainSeedHex: String?
                if isInitiateDevice {
                    guard let chainKey, let serializedChainSeed = Data.clampThenUniformScalar(from: chainKey) else {
                        throw HelperError.runtimeError("Couldn't transform key to scalar for Schnorr key import for chain \(chain.name)")
                    }
                    chainSeedHex = serializedChainSeed.hexString
                }
                let schnorr = makeSchnorrKeygen(localUI: chainSeedHex)
                jobs.append(KeyImportChainJob(chain: chain, isEddsa: true, routing: routing, dkls: nil, schnorr: schnorr))
            }
        }
        return jobs
    }

    nonisolated private static func prepareChainImportJob(_ job: KeyImportChainJob) async throws {
        if let dkls = job.dkls {
            try await dkls.prepareKeyImportSetup(routing: job.routing)
            return
        }
        if let schnorr = job.schnorr {
            try await schnorr.prepareKeyImportSetup(routing: job.routing)
            return
        }
        throw HelperError.runtimeError("invalid chain import job for \(job.chain.name)")
    }

    nonisolated private static func executeChainImportJob(_ job: KeyImportChainJob) async throws -> KeyImportChainResult {
        if let dkls = job.dkls {
            try await dkls.DKLSKeygenWithRetry(attempt: 0, routing: job.routing)
            guard let keyshare = dkls.getKeyshare() else {
                throw HelperError.runtimeError("fail to get ECDSA keyshare for chain \(job.chain.name)")
            }
            return KeyImportChainResult(chain: job.chain, keyshare: keyshare, isEddsa: false)
        }
        if let schnorr = job.schnorr {
            try await schnorr.SchnorrKeygenWithRetry(attempt: 0, routing: job.routing)
            guard let keyshare = schnorr.getKeyshare() else {
                throw HelperError.runtimeError("fail to get EdDSA keyshare for chain \(job.chain.name)")
            }
            return KeyImportChainResult(chain: job.chain, keyshare: keyshare, isEddsa: true)
        }
        throw HelperError.runtimeError("invalid chain import job for \(job.chain.name)")
    }

    private func makeDklsKeygen(localUI: String?) -> DKLSKeygen {
        DKLSKeygen(vault: self.vault,
                   tssType: self.tssType,
                   keygenCommittee: self.keygenCommittee,
                   vaultOldCommittee: self.vaultOldCommittee,
                   mediatorURL: self.mediatorURL,
                   sessionID: self.sessionID,
                   encryptionKeyHex: self.encryptionKeyHex,
                   isInitiateDevice: self.isInitiateDevice,
                   localUI: localUI)
    }

    private func makeSchnorrKeygen(localUI: String?) -> SchnorrKeygen {
        SchnorrKeygen(vault: self.vault,
                      tssType: self.tssType,
                      keygenCommittee: self.keygenCommittee,
                      vaultOldCommittee: self.vaultOldCommittee,
                      mediatorURL: self.mediatorURL,
                      sessionID: self.sessionID,
                      encryptionKeyHex: self.encryptionKeyHex,
                      isInitiatedDevice: self.isInitiateDevice,
                      setupMessage: [UInt8](),
                      localUI: localUI)
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

    private struct KeyImportChainJob: @unchecked Sendable {
        let chain: Chain
        let isEddsa: Bool
        let routing: KeygenRouting
        let dkls: DKLSKeygen?
        let schnorr: SchnorrKeygen?
    }

    private struct KeyImportChainResult: @unchecked Sendable {
        let chain: Chain
        let keyshare: DKLSKeyshare
        let isEddsa: Bool
    }

    // Create DKLS vault via keygen or reshare
    // This function is also used for private key import , but mostly for import root private keys(both ECDSA and EdDSA)
    func startKeygenDKLS(context: ModelContext, localUIEcdsa: String? = nil, localUIEddsa: String? = nil) async {
        await updateProgress(50)
        do {
            let isTssBatchEnabled = await FeatureFlagService().isFeatureEnabled(feature: .TssBatch)
            let useParallelPath = isTssBatchEnabled && (self.tssType == .Keygen || self.tssType == .Migrate || self.tssType == .Reshare)
            self.logger.info("\(self.tssType.rawValue) flow starting: execution=\(useParallelPath ? "parallel" : "sequential"), tssBatchEnabled=\(isTssBatchEnabled)")

            let dklsKeygen = DKLSKeygen(vault: self.vault,
                                        tssType: self.tssType,
                                        keygenCommittee: self.keygenCommittee,
                                        vaultOldCommittee: self.vaultOldCommittee,
                                        mediatorURL: self.mediatorURL,
                                        sessionID: self.sessionID,
                                        encryptionKeyHex: self.encryptionKeyHex,
                                        isInitiateDevice: self.isInitiateDevice,
                                        localUI: localUIEcdsa)

            if useParallelPath {
                // Parallel: ECDSA and EdDSA run concurrently with isolated relay namespaces.
                // Schnorr gets empty setupMessage — for keygen it downloads the shared setup
                // from relay on demand; for reshare each protocol creates its own setup message.
                let schnorrKeygen = SchnorrKeygen(vault: self.vault,
                                                  tssType: self.tssType,
                                                  keygenCommittee: self.keygenCommittee,
                                                  vaultOldCommittee: self.vaultOldCommittee,
                                                  mediatorURL: self.mediatorURL,
                                                  sessionID: self.sessionID,
                                                  encryptionKeyHex: self.encryptionKeyHex,
                                                  isInitiatedDevice: self.isInitiateDevice,
                                                  setupMessage: [UInt8](),
                                                  localUI: localUIEddsa)

                let ecdsaRouting = KeygenRouting.from(exchangeMessageId: KeygenMessageId.rootECDSA)
                let eddsaRouting = KeygenRouting.from(exchangeMessageId: KeygenMessageId.rootEdDSA)

                if self.tssType == .Reshare {
                    // Reshare: each protocol creates its own setup message, so setup also needs routing.
                    let ecdsaReshareRouting = KeygenRouting.from(
                        setupMessageId: KeygenMessageId.rootECDSA,
                        exchangeMessageId: KeygenMessageId.rootECDSA
                    )
                    let eddsaReshareRouting = KeygenRouting.from(
                        setupMessageId: KeygenMessageId.rootEdDSA,
                        exchangeMessageId: KeygenMessageId.rootEdDSA
                    )
                    self.status = .ReshareECDSA
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await dklsKeygen.DKLSReshareWithRetry(attempt: 0, routing: ecdsaReshareRouting)
                        }
                        group.addTask {
                            try await schnorrKeygen.SchnorrReshareWithRetry(attempt: 0, routing: eddsaReshareRouting)
                        }
                        try await group.waitForAll()
                    }
                } else {
                    // Keygen / Migrate: shared setup message, only exchange needs routing.
                    self.status = .KeygenECDSA
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await dklsKeygen.DKLSKeygenWithRetry(attempt: 0, routing: ecdsaRouting)
                        }
                        group.addTask {
                            try await schnorrKeygen.SchnorrKeygenWithRetry(attempt: 0, routing: eddsaRouting)
                        }
                        try await group.waitForAll()
                    }
                }

                await updateProgress(100)

                try await finalizeDKLSKeygen(dklsKeygen: dklsKeygen, schnorrKeygen: schnorrKeygen, context: context)
                return
            }

            // Sequential path (flag off, or key import which has its own parallel handling).
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
            case .SingleKeygen:
                break
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
            case .SingleKeygen:
                break
            }

            await updateProgress(100)

            try await finalizeDKLSKeygen(dklsKeygen: dklsKeygen, schnorrKeygen: schnorrKeygen, context: context)
        } catch {
            self.logger.error("Failed to generate DKLS key, error: \(error.localizedDescription)")
            self.status = .KeygenFailed
            self.keygenError = error.localizedDescription
            return
        }
    }

    private func finalizeDKLSKeygen(dklsKeygen: DKLSKeygen, schnorrKeygen: SchnorrKeygen, context: ModelContext) async throws {
        self.vault.signers = self.keygenCommittee
        let keyshareECDSA = dklsKeygen.getKeyshare()
        let keyshareEdDSA = schnorrKeygen.getKeyshare()

        guard let keyshareECDSA else {
            throw HelperError.runtimeError("fail to get ECDSA keyshare")
        }
        guard let keyshareEdDSA else {
            throw HelperError.runtimeError("fail to get EdDSA keyshare")
        }

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
            self.vault.libType = .DKLS
        }
        self.vault.keyshares = [KeyShare(pubkey: keyshareECDSA.PubKey, keyshare: keyshareECDSA.Keyshare),
                                KeyShare(pubkey: keyshareEdDSA.PubKey, keyshare: keyshareEdDSA.Keyshare)]

        let needsInsert = self.tssType == .Keygen ||
            !self.vaultOldCommittee.contains(self.vault.localPartyID)

        if needsInsert {
            let shouldProceed = await confirmDuplicateVaultIfNeeded(context: context)
            if !shouldProceed {
                self.didCancelDuplicateVault = true
                return
            }
            VaultDefaultCoinService(context: context)
                .setDefaultCoinsOnce(vault: self.vault)
            context.insert(self.vault)
        }

        try context.save()
        self.status = .KeygenFinished
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
            self.tssService = try await self.createTssInstance()
            guard let tssService = self.tssService else {
                throw HelperError.runtimeError("TSS instance is nil")
            }
            try await keygenWithRetry(tssIns: tssService, attempt: 1)
            self.vault.signers = self.keygenCommittee
            // save the vault
            if let stateAccess {
                self.vault.keyshares = stateAccess.keyshares
            }

            let needsInsert: Bool
            switch self.tssType {
            case .Keygen:
                needsInsert = true
            case .Reshare:
                needsInsert = !self.vaultOldCommittee.contains(self.vault.localPartyID)
            case .Migrate:
                self.logger.error("Failed to migration vault")
                self.status = .KeygenFailed
                return
            case .KeyImport:
                self.logger.error("Failed to key import vault")
                self.status = .KeygenFailed
                return
            case .SingleKeygen:
                self.logger.error("SingleKeygen should not reach GG20 path")
                self.status = .KeygenFailed
                return
            }

            if needsInsert {
                let shouldProceed = await confirmDuplicateVaultIfNeeded(context: context)
                if !shouldProceed {
                    self.didCancelDuplicateVault = true
                    return
                }
                VaultDefaultCoinService(context: context)
                    .setDefaultCoinsOnce(vault: self.vault)
                context.insert(self.vault)
            }

            try context.save()
            self.status = .KeygenFinished
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
            case .SingleKeygen:
                throw HelperError.runtimeError("SingleKeygen should not reach GG20 path")
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

    private func createTssInstance() async throws -> TssServiceImpl? {
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
            case .MLDSA:
                throw HelperError.runtimeError("MLDSA keygen is not supported via GG20 TSS service")
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
            case .MLDSA:
                throw HelperError.runtimeError("MLDSA reshare is not supported via GG20 TSS service")
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
