//
//  KeyshareEncryptionMigration.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import OSLog
import SwiftData

private let logger = Log.app.store

/// Encrypts every vault's key shares at rest, once.
///
/// This is the only step in the passcode feature that rewrites key material, and
/// a mistake here is lost funds rather than a bad screen. The ordering below is
/// the whole safety argument and should not be rearranged:
///
/// 1. Generate the data key and persist it, then **read it back and compare**.
///    Encrypting against a key that was never durably stored produces shares
///    nobody can open.
/// 2. Seal every share **in memory**.
/// 3. **Open each sealed value again and check it equals the original.** A share
///    is only replaced once it has been proved recoverable.
/// 4. Only then write to the model and save.
///
/// Any failure aborts with the plaintext untouched, and `AppMigrationService`
/// leaves the version un-bumped so the next launch retries. Retrying is safe
/// because sealed values are self-describing: `KeyshareProtector.seal` returns
/// an already-sealed value unchanged, so a partially migrated store completes
/// rather than double-sealing.
///
/// A note for whoever writes the next migration that touches key shares: once a
/// passcode is set, the data key is wrapped and unavailable at launch, so
/// `AppMigrationService` — which runs before any unlock — cannot open shares.
/// Any future keyshare-touching migration has to run **after** unlock instead.
struct KeyshareEncryptionMigration: @MainActor AppMigration {

    enum MigrationError: Error, Equatable {
        case missingModelContext
        /// A sealed share did not open back to its original value.
        case verificationFailed(pubkey: String)
        /// Sealed shares exist but no data key could be read.
        case dataKeyUnavailable
    }

    let version: Int = 4

    let description: String = "Encrypting vault key shares at rest"

    private let keyStore: KeyshareKeyStoring
    private let session: KeyshareKeySession
    private let protector: KeyshareProtecting

    init(
        keyStore: KeyshareKeyStoring = DefaultKeyshareKeyStore.shared,
        session: KeyshareKeySession = .shared,
        protector: KeyshareProtecting = KeyshareProtector.shared
    ) {
        self.keyStore = keyStore
        self.session = session
        self.protector = protector
    }

    @MainActor
    func migrate() throws {
        guard let modelContext = Storage.shared.modelContext else {
            throw MigrationError.missingModelContext
        }

        let vaults = try modelContext.fetch(FetchDescriptor<Vault>())
        guard !vaults.isEmpty else {
            logger.info("No vaults to encrypt")
            return
        }

        // Whether anything is already sealed decides how a missing data key has
        // to be handled, so it is established before the key is touched.
        let hasSealedShares = vaults.contains { vault in
            vault.keyshares.contains { protector.isSealed($0.keyshare) }
        }
        try prepareDataKey(hasSealedShares: hasSealedShares)

        // Phase 1 — seal and verify everything, mutating nothing. Applying a
        // vault as soon as it verifies would leave earlier vaults already
        // changed in the live context when a later one fails; the version stays
        // un-bumped, but an autosave or any unrelated save could still flush
        // that half-migrated state to disk.
        var pending: [(vault: Vault, shares: [KeyShare])] = []
        for vault in vaults {
            if let sealed = try sealedShares(of: vault) {
                pending.append((vault, sealed))
            }
        }

        guard !pending.isEmpty else {
            logger.info("Key shares are already encrypted")
            return
        }

        // Phase 2 — every share across every vault has now been proved
        // recoverable, so the writes can go in together.
        for entry in pending {
            entry.vault.keyshares = entry.shares
        }

        // Phase 3 — persist, discarding the in-memory changes if the write
        // fails so the context cannot carry a partial migration forward.
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            logger.error("Save failed, rolled back: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let sealedCount = pending.reduce(0) { $0 + $1.shares.count }
        logger.info("Encrypted \(sealedCount, privacy: .public) key shares across \(pending.count, privacy: .public) vaults")
    }

    /// Makes a data key available and proves it is durable before anything is
    /// encrypted with it. Reuses an existing key so a retry after a partial run
    /// can still open what the previous attempt sealed.
    ///
    /// - Parameter hasSealedShares: whether any stored share is already
    ///   ciphertext. This is the difference between a first run and a dangerous
    ///   one: `loadDataKey` returns `nil` for *any* failure, not only for an
    ///   absent item, and `AppMigrationService` reads its version from the same
    ///   Keychain — so a transient Keychain failure can both re-run a completed
    ///   migration and hide the existing key. Generating a replacement at that
    ///   moment would orphan every sealed share permanently. Aborting instead
    ///   costs a retry on the next launch.
    @MainActor
    private func prepareDataKey(hasSealedShares: Bool) throws {
        if let existing = keyStore.loadDataKey() {
            session.adopt(existing)
            return
        }

        guard !hasSealedShares else {
            logger.error("Key shares are sealed but no data key could be read; aborting rather than replacing it")
            throw MigrationError.dataKeyUnavailable
        }

        let key = try keyStore.generateDataKey()
        // Throws unless the write reads back byte-identical.
        try keyStore.storeDataKey(key)
        session.adopt(key)
    }

    /// The vault's shares, sealed and each verified to open back to its
    /// original. Returns `nil` when nothing needs changing.
    ///
    /// Builds a whole array and lets the caller assign it through the property
    /// setter. Assigning into an element (`keyshares[i] = …`) is not a
    /// dependable way to mark a `@Model` dirty, and a migration that reported
    /// success while persisting nothing would still record its version and
    /// never run again.
    @MainActor
    private func sealedShares(of vault: Vault) throws -> [KeyShare]? {
        var result: [KeyShare] = []
        var changed = false

        for share in vault.keyshares {
            let stored = share.keyshare

            // Sealed by an earlier attempt. Authenticate it rather than assume:
            // a share sealed under a key we no longer hold would otherwise ride
            // through untouched, let the migration report success, and bump the
            // version — so the vault is dead and nothing ever revisits it.
            if protector.isSealed(stored) {
                do {
                    _ = try protector.open(stored)
                } catch {
                    logger.error("An already-sealed key share could not be opened; aborting")
                    throw MigrationError.verificationFailed(pubkey: share.pubkey)
                }
                result.append(share)
                continue
            }

            let sealed = try protector.seal(stored)
            guard try protector.open(sealed) == stored else {
                logger.error("Round-trip verification failed for a key share; leaving plaintext untouched")
                throw MigrationError.verificationFailed(pubkey: share.pubkey)
            }

            result.append(KeyShare(pubkey: share.pubkey, keyshare: sealed, keyId: share.keyId))
            changed = true
        }

        return changed ? result : nil
    }
}
