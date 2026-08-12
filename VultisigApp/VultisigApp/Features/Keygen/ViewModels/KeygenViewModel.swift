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

/// `commitVault` is `static`, so it cannot reach the view model's own logger.
private let commitLogger = Log.keygen.viewModel

/// Why a finished vault could not be committed to the store.
enum KeygenCommitError: Error, Equatable, LocalizedError {
    /// A share about to be persisted cannot be turned back into a share under
    /// the protection state in force right now. Carries the share's public key.
    case unreadableKeyshare(pubkey: String)

    /// A share about to be persisted reads back fine but cannot be protected
    /// under the state in force right now, so persisting it would put plaintext
    /// key material into a protected store.
    ///
    /// The split is by *operation* — could not be read back, could not be
    /// protected — and nothing finer, because nothing finer is knowable here. A
    /// locked app produces one or the other depending only on which form the
    /// shares happen to be in, and neither case can tell a recoverable lock from
    /// a key that is gone. What the two do earn is separate copy: "we could not
    /// read this" and "we could not protect this" are different sentences, and
    /// pointing both at the first would make the second one false.
    case unsealableKeyshare(pubkey: String)

    /// The store is carrying uncommitted work from somewhere else, and this
    /// commit would have to insert a vault it could only take back by
    /// discarding that work with it.
    ///
    /// Refused rather than resolved, and the three ways of resolving it were
    /// each tried and rejected: flushing the other work commits a half-finished
    /// flow because the user tapped a button on this one; rolling it back
    /// discards it; and deleting only this vault's own row strips the caller's
    /// object of its coins and chain public keys through the cascade, so the
    /// retry stores a vault that no longer knows which chains it can derive.
    ///
    /// Transient: any `save()` from anywhere settles the context — the main
    /// context autosaves — and the same button then works. It is the same
    /// answer `KeyshareSweeper` gives to a dirty context, for the same reason.
    case busy

    init(_ failure: KeyshareNormalizationFailure) {
        switch failure {
        case .unreadable(let pubkey):
            self = .unreadableKeyshare(pubkey: pubkey)
        case .unsealable(let pubkey, _):
            self = .unsealableKeyshare(pubkey: pubkey)
        }
    }

    /// The review screen renders `error.localizedDescription`. Without this the
    /// alert would fall back to the raw `NSError` form and tell the user
    /// nothing about what actually happened.
    ///
    /// The copy states only what is known. `open` reports a key that is gone, a
    /// key that does not fit, and a key merely not yet unwrapped as the same two
    /// errors, so naming a cause here would assert something the check cannot
    /// establish — and two of the three are recoverable by unlocking.
    var errorDescription: String? {
        switch self {
        case .unreadableKeyshare:
            return "keysharesUnreadableVaultNotSaved".localized
        case .unsealableKeyshare:
            return "keysharesUnsealableVaultNotSaved".localized
        case .busy:
            return "somethingWentWrongTryAgain".localized
        }
    }
}

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
    private let logger = Log.keygen.tss

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
    var isTssBatch: Bool = false

    /// When `true`, a brand-new vault is *not* inserted/saved when keygen finishes;
    /// persistence is deferred to the "Review Your Vaults" confirmation
    /// (`KeygenViewModel.commitVault`). This guarantees an aborted secure keygen
    /// discards the vault on every exit path (back, "Something's wrong", app kill),
    /// keeping the vault name reusable. The fast path persists immediately because
    /// it manages its own abort cleanup at the email-verification step.
    var deferVaultPersistence: Bool = false

    @Published var isLinkActive = false
    @Published var keygenError: String = ""
    @Published var status = KeygenStatus.CreatingInstance
    @Published var progress: Float = 0.0
    @Published var showDuplicateVaultAlert = false
    @Published var duplicateVaultName: String = ""
    @Published var didCancelDuplicateVault = false
    @Published var keygenConnected = false

    /// Held for the whole vault-creation episode, so a passcode transition
    /// cannot land between the TSS layer producing a share and this flow
    /// persisting it.
    ///
    /// Released by being set to `nil`, or by this view model going away — the
    /// lease releases on `deinit`, which is what stops an unhandled path from
    /// stranding it and blocking every later passcode change until relaunch.
    private var keygenEpisode: EpisodeLease?

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
                 singleKeygenType: SingleKeygenType? = nil,
                 isTssBatch: Bool = false,
                 deferVaultPersistence: Bool = false
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
        self.isTssBatch = isTssBatch
        self.deferVaultPersistence = deferVaultPersistence
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

    /// Persists a freshly generated vault into SwiftData.
    ///
    /// For the secure keygen flow this is intentionally called from the
    /// "Review Your Vaults" confirmation ("Looks Good") rather than the moment
    /// keygen finishes, so that aborting the review screen discards the vault and
    /// leaves its name reusable. Inserting on the unique `pubKeyECDSA` upserts, so
    /// re-running keygen that reproduces an existing vault replaces it as before.
    ///
    /// Not every vault reaching here is new. A secure reshare on a device that
    /// was already a signer has already had its reshared vault saved by
    /// `finalizeDKLSKeygen`'s `needsInsert == false` branch and still comes
    /// through the review screen, so this also runs over vaults that are already
    /// stored. The insert is then the upsert described above, and the undo below
    /// must not treat that row as its own.
    ///
    /// **All of it or none of it.** A throwing `save()` writes nothing to the
    /// store, but it leaves the vault and its coins registered in a context the
    /// whole app shares — and a fetch resolves a pending insert, so the app would
    /// go on believing in a wallet the user was just told could not be saved,
    /// until something unrelated flushed it for real. Whatever this put in the
    /// context is taken back, the vault is handed back in the form it arrived in,
    /// and the failure is surfaced. Retrying is the caller's to decide: "Looks
    /// Good" runs the whole thing again under a fresh lease, which is the right
    /// granularity for the failures a save actually produces here — the container
    /// unreachable, data protection unavailable, the disk full — none of which a
    /// second attempt one line later would fix.
    ///
    /// - Parameter save: the store write. A seam, and only a seam: SwiftData
    ///   offers no way to make an in-memory `save()` fail on demand, and the
    ///   path that matters most here is the one a save failure opens.
    @MainActor
    static func commitVault(
        _ vault: Vault,
        context: ModelContext,
        protector: KeyshareProtecting = KeyshareProtector.shared,
        save: @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let coinService = VaultDefaultCoinService(context: context)

        // The insert and the save are one write span. The episode lease already
        // keeps a transition out of the whole review interval, but this is the
        // moment the shares actually reach the store, so it carries its own
        // guarantee rather than relying on a lease held elsewhere. The undo
        // below is inside the span for the same reason: a transition must not
        // land between a failed save and the withdrawal that takes it back.
        try KeyshareWriteCoordinator.shared.withWriteLease {
            // Ahead of everything else, so a refusal leaves the context exactly
            // as it found it — `setDefaultCoinsOnce` builds coins onto the vault.
            let shares = try normalizedKeyshares(of: vault, protector: protector)

            // Whatever the context was already carrying decides how a failure
            // can be undone, and it has to be sampled before the first mutation.
            let wasCarryingOtherWork = context.hasChanges

            // Nothing may be committed over a vault the context is on its way to
            // deleting: the save would remove it and this would report success.
            // Nothing before the review screen marks one that way, so this is
            // insurance rather than a live case, and it costs one read.
            guard !vault.isDeleted else {
                commitLogger.error("Refusing to persist a vault the context is holding as deleted")
                throw KeygenCommitError.busy
            }

            // Whether this call is the one bringing the vault into the store.
            // Not every vault reaching here is new: a secure reshare on a device
            // that was already a signer arrives with one that is already stored,
            // and the two cases have different undos.
            //
            // Asked of the *store* and not of `vault.modelContext`, which only
            // says the object is registered — a pending insert is registered and
            // is not stored, and reading it as stored would leave that insert
            // behind on the branch below, which is this whole bug over again. A
            // context of its own reads durable rows only, so a hit is proof.
            let isNewToTheStore = !isStored(vault, in: context)

            // A vault this call has to *insert* can only be taken back by a
            // `rollback()`, and a rollback is only this commit's to run when the
            // context was clean on the way in. So a context carrying somebody
            // else's uncommitted work is refused here, before anything is
            // touched. The alternatives were each tried: flushing that work
            // commits a half-finished flow because the user tapped a button on
            // this one, rolling back discards it, and deleting just this
            // vault's row strips the caller's object through the cascade — see
            // ``KeygenCommitError.busy``.
            guard !(isNewToTheStore && wasCarryingOtherWork) else {
                commitLogger.error("Refusing to persist a vault: the store is carrying work this commit could not take back")
                throw KeygenCommitError.busy
            }

            // The shares as they were handed over. A failed save has to give
            // them back in that form and not in the one this commit computed —
            // see ``restore(_:to:)``. The coins the vault already held are what
            // tells the undo which rows are this call's to take back.
            let previousShares = vault.keyshares
            let previousCoins = vault.coins
            let previousDefiChains = vault.defiChains

            // Whole-array assignment, never element assignment: assigning into
            // an element is not a dependable way to mark a `@Model` dirty.
            vault.keyshares = shares

            coinService.setDefaultCoinsOnce(vault: vault)
            context.insert(vault)

            do {
                try save(context)
            } catch {
                // A throwing save writes nothing, so the *store* is intact — but
                // the vault and its coins stay pending in a context the whole app
                // shares, and SwiftData resolves pending inserts in every fetch.
                // Left alone they would show up as a wallet the user was just
                // told could not be saved, and the next autosave or any
                // unrelated `save()` would make that durable *outside* this
                // lease, where a passcode transition can land between the
                // normalization and the write.
                withdraw(
                    vault,
                    from: context,
                    rollingBack: !wasCarryingOtherWork,
                    coinsItAlreadyHeld: previousCoins,
                    defiChainsItAlreadyHad: previousDefiChains
                )
                restore(vault, to: previousShares)
                commitLogger.error("Vault commit failed to save: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        // Past every way this can refuse, so the network work it starts is
        // aimed at a vault that is provably stored and cannot be withdrawn.
        coinService.startTokenDiscovery()
    }

    /// Takes back what this commit put in the context, without taking anybody
    /// else's work with it.
    ///
    /// Over a context that was clean on the way in, everything pending is
    /// provably this commit's and `rollback()` is the right primitive: it
    /// discards the insert and leaves the caller's vault whole and
    /// re-insertable, which is what makes the next "Looks Good" a real retry.
    ///
    /// Over a context that was not clean, the vault is one the store already
    /// holds — the guard above refuses the other case — so the row is not this
    /// call's to remove and only the coins it attached come back out. Detached
    /// from the coin's side before the delete, for the same reason
    /// `VaultDefaultCoinService` detaches before taking a coin back: on a vault
    /// that has been through a `save()` the to-one write is the one that takes.
    ///
    /// **Do not "simplify" this to `context.delete(vault)` on both branches.**
    /// The row does go back, and then the `.cascade` on `Vault.coins` and
    /// `Vault.chainPublicKeys` strips the caller's *object* — so the retry,
    /// which is the whole point of surfacing rather than swallowing, rebuilds a
    /// key-import vault that no longer knows which chains it can derive and
    /// stores it with none. Measured, and not even deterministic run to run.
    @MainActor
    private static func withdraw(
        _ vault: Vault,
        from context: ModelContext,
        rollingBack: Bool,
        coinsItAlreadyHeld previousCoins: [Coin],
        defiChainsItAlreadyHad previousDefiChains: [Chain]
    ) {
        guard !rollingBack else {
            context.rollback()
            return
        }

        for coin in vault.coins where !previousCoins.contains(where: { $0 === coin }) {
            coin.vault = nil
            context.delete(coin)
        }

        // The DeFi chains go back with the coins they were derived from, and
        // only on this branch. `setDefaultCoins` writes both together, so
        // taking the coins away and leaving the chains would persist a vault
        // offering DeFi on chains it holds no coin for. The rollback branch
        // must *not* do this: it leaves the coin objects attached, and a
        // preparation that finds coins already there does not recompute the
        // chains, so reverting them there would drop them for good.
        vault.defiChains = previousDefiChains
    }

    /// Whether the store already holds this vault, asked through a context of
    /// its own so that only durable rows can answer.
    ///
    /// `vault.modelContext != nil` is the cheap version and it is wrong: it is
    /// also true of a pending insert, which is registered and not stored.
    @MainActor
    private static func isStored(_ vault: Vault, in context: ModelContext) -> Bool {
        let pubKeyECDSA = vault.pubKeyECDSA
        guard !pubKeyECDSA.isEmpty else { return false }

        var descriptor = FetchDescriptor<Vault>(
            predicate: #Predicate<Vault> { $0.pubKeyECDSA == pubKeyECDSA }
        )
        descriptor.fetchLimit = 1
        return ((try? ModelContext(context.container).fetch(descriptor).first) ?? nil) != nil
    }

    /// Puts the vault's shares back in the form they were handed over in.
    ///
    /// Not tidiness, and not something the rollback does — a rolled-back object
    /// keeps the property values it was given. Normalizing rewrites the caller's
    /// vault in place, so a commit that sealed plaintext shares and then failed
    /// to save leaves the review screen holding sealed ones. Disable the passcode
    /// before retrying and those shares no longer open under any state: the
    /// retry refuses, permanently, over a vault that would have committed fine.
    /// The undo is only total if it reaches the object as well as the context.
    ///
    /// The shares and nothing else. `coins` and `defiChains` are the coin
    /// preparation's own output, it is idempotent over them, and a rollback
    /// leaves the coin objects attached to the vault — so reverting `defiChains`
    /// while the coins stay would make the retry store a vault whose DeFi chains
    /// were silently dropped, because a preparation that finds coins already
    /// there does not recompute them. They carry no key material; the shares do,
    /// and the shares are the mismatch nothing can recover from.
    @MainActor
    private static func restore(_ vault: Vault, to shares: [KeyShare]) {
        vault.keyshares = shares
    }

    /// The vault's shares in the form the current protection state requires,
    /// computed before any of them is persisted.
    ///
    /// The write lease above only excludes a transition running *concurrently*
    /// with the insert; one that has already finished leaves nothing to exclude.
    /// And the deferred-persistence flow holds its shares in memory across the
    /// whole review screen, where the sweep cannot reach them — so whichever way
    /// the passcode moved during the review, these shares missed it:
    ///
    /// - Disabled during the review, and the sweep unsealed every *stored* share
    ///   and deleted the data key without ever seeing these. Persisting them
    ///   stores a vault sealed under a key that no longer exists: it looks
    ///   complete, nothing revisits it, and every signature it is asked for
    ///   fails. Nothing here can repair that, so it is refused.
    /// - Set during the review, and the sweep sealed every *stored* share
    ///   without ever seeing these. Persisting them puts plaintext key material
    ///   into a store with an active passcode, readable while the app is locked
    ///   and left that way, because the sweep has already run. That one *is*
    ///   repairable — sealing it here is the repair — and refusing instead would
    ///   destroy a finished keygen to prevent an exposure this very write ends.
    ///
    /// So the shares are normalized rather than merely checked, by the same
    /// ``KeyshareNormalizer`` a backup import uses across its own gap. Verifying
    /// alone would close only the first case: plaintext is readable.
    @MainActor
    private static func normalizedKeyshares(
        of vault: Vault,
        protector: KeyshareProtecting
    ) throws -> [KeyShare] {
        do {
            return try KeyshareNormalizer(protector: protector).normalizedShares(of: vault)
        } catch let failure as KeyshareNormalizationFailure {
            // The share is named here as well as in the normalizer's own line:
            // a vault carries one share per curve and key import adds one per
            // chain, and the alert the user sees carries no pubkey at all.
            let refusal = KeygenCommitError(failure)
            commitLogger.error("Refusing to persist a vault: \(String(describing: refusal), privacy: .public)")
            throw refusal
        }
    }

    func startKeygen(context: ModelContext) async {
        self.keygenConnected = true

        // A passcode transition is rewriting every stored share while it runs,
        // and a keygen started underneath it would produce a share the sweep
        // never sees. Transitions are short foreground actions, so the honest
        // answer is to refuse and let the user retry.
        guard let episode = KeyshareWriteCoordinator.shared.beginEpisode() else {
            logger.error("Keygen refused: a passcode transition holds the key-share coordinator")
            self.status = .KeygenFailed
            self.keygenError = "somethingWentWrongTryAgain".localized
            return
        }
        self.keygenEpisode = episode

        // Every path below either persists the vault before returning or fails
        // outright. The deferred flow is the exception: it leaves sealed shares
        // in memory waiting for the review screen to confirm, and that interval
        // is exactly what the episode exists to cover, so its lease outlives
        // this call and goes when this view model does.
        defer {
            if !(self.deferVaultPersistence && self.status == .KeygenFinished) {
                self.keygenEpisode = nil
            }
        }

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

                // Sealed before this party reports completion. Sealing can fail,
                // and once the peers have been told keygen succeeded there is no
                // longer a safe way to abandon the share — the vault would be
                // left holding a public key whose share was never stored.
                let mldsaShare = try KeyShare.sealed(
                    pubkey: keyshare.PubKey,
                    keyshare: keyshare.Keyshare,
                    keyId: keyshare.keyId
                )

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
                self.vault.keyshares.append(mldsaShare)
                self.vault.isBackedUp = false
            }

            try context.save()
            // Broadcast completion so pending QBTC follow-ups (token-
            // selection intercept, BTC chain-detail claim banner) can
            // finish their "add QBTC + show claim" handoff without
            // threading a closure through the keygen routes.
            QuantumKeygenNotification.postCompleted(vaultPubKeyECDSA: self.vault.pubKeyECDSA)
            self.status = .KeygenFinished
        } catch {
            self.logger.error("Failed to generate MLDSA key, error: \(error.localizedDescription)")
            self.status = .KeygenFailed
            self.keygenError = error.localizedDescription
        }
    }

    func startKeyImportKeygen(modelContext: ModelContext) async throws {
        let useParallelPath = self.isTssBatch
        self.logger.info("KeyImport flow starting: execution=\(useParallelPath ? "parallel" : "sequential")")

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

        // Seal every share up front so the vault is not left holding chain
        // public keys whose shares never made it in.
        var sealedChainShares: [KeyShare] = []
        for result in chainResults where seenPubKeys.insert(result.keyshare.PubKey).inserted {
            sealedChainShares.append(
                try KeyShare.sealed(pubkey: result.keyshare.PubKey, keyshare: result.keyshare.Keyshare)
            )
        }

        self.vault.keyshares.append(contentsOf: sealedChainShares)
        for result in chainResults {
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
            // Deferred persistence (secure flow): do NOT touch the context here.
            // `setDefaultCoins` inserts coins, so running it before the review
            // confirmation would leave orphan rows the autosave could flush.
            // `KeygenViewModel.commitVault` does the full insert at "Looks Good".
            if !self.deferVaultPersistence {
                let coinService = VaultDefaultCoinService(context: modelContext)
                coinService.setDefaultCoinsOnce(vault: self.vault)
                modelContext.insert(self.vault)
                try modelContext.save()
                // Only once the save has landed. Token discovery outlives this
                // call and writes on its own, so a vault whose save threw must
                // never have it pointed at it.
                coinService.startTokenDiscovery()
            }
        } else {
            try modelContext.save()
        }

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

        let sealedRootShares = [
            try KeyShare.sealed(pubkey: rootEcdsa.PubKey, keyshare: rootEcdsa.Keyshare),
            try KeyShare.sealed(pubkey: rootEddsa.PubKey, keyshare: rootEddsa.Keyshare)
        ]

        self.vault.pubKeyECDSA = rootEcdsa.PubKey
        self.vault.pubKeyEdDSA = rootEddsa.PubKey
        self.vault.hexChainCode = rootEcdsa.chaincode
        self.vault.keyshares.append(contentsOf: sealedRootShares)
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
            let useParallelPath = self.isTssBatch && (self.tssType == .Keygen || self.tssType == .Migrate || self.tssType == .Reshare)
            self.logger.info("\(self.tssType.rawValue) flow starting: execution=\(useParallelPath ? "parallel" : "sequential")")

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

        // Sealed before this party reports completion, for the same reason as
        // above: after markLocalPartyComplete the peers consider the vault
        // created, so a sealing failure has nowhere left to abort to.
        let sealedShares = [
            try KeyShare.sealed(pubkey: keyshareECDSA.PubKey, keyshare: keyshareECDSA.Keyshare),
            try KeyShare.sealed(pubkey: keyshareEdDSA.PubKey, keyshare: keyshareEdDSA.Keyshare)
        ]

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
        self.vault.keyshares = sealedShares

        let needsInsert = self.tssType == .Keygen ||
            !self.vaultOldCommittee.contains(self.vault.localPartyID)

        if needsInsert {
            let shouldProceed = await confirmDuplicateVaultIfNeeded(context: context)
            if !shouldProceed {
                self.didCancelDuplicateVault = true
                return
            }
            // Deferred persistence (secure flow): do NOT touch the context here.
            // `setDefaultCoins` inserts coins, so running it before the review
            // confirmation would leave orphan rows the autosave could flush.
            // `KeygenViewModel.commitVault` does the full insert at "Looks Good".
            if !self.deferVaultPersistence {
                let coinService = VaultDefaultCoinService(context: context)
                coinService.setDefaultCoinsOnce(vault: self.vault)
                context.insert(self.vault)
                try context.save()
                // Only once the save has landed. Token discovery outlives this
                // call and writes on its own, so a vault whose save threw must
                // never have it pointed at it.
                coinService.startTokenDiscovery()
            }
        } else {
            try context.save()
        }

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
                // Deferred persistence (secure flow): do NOT touch the context here.
                // `setDefaultCoins` inserts coins, so running it before the review
                // confirmation would leave orphan rows the autosave could flush.
                // `KeygenViewModel.commitVault` does the full insert at "Looks Good".
                if !self.deferVaultPersistence {
                    let coinService = VaultDefaultCoinService(context: context)
                    coinService.setDefaultCoinsOnce(vault: self.vault)
                    context.insert(self.vault)
                    try context.save()
                    // Only once the save has landed. Token discovery outlives
                    // this call and writes on its own, so a vault whose save
                    // threw must never have it pointed at it.
                    coinService.startTokenDiscovery()
                }
            } else {
                try context.save()
            }

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
