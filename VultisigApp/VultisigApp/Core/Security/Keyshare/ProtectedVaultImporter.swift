//
//  ProtectedVaultImporter.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftData

private let logger = Log.app.store

enum ProtectedVaultImportError: Error, Equatable {
    /// A passcode transition is in progress. The import is refused rather than
    /// queued: the transition is about to rewrite every stored share, and a
    /// vault inserted underneath it would never be seen.
    case busy
    /// An incoming share is sealed and does not open here — the wrong key, or a
    /// value that is not a share at all.
    case unreadableShare(pubkey: String)
}

/// The one way an imported vault reaches storage.
///
/// Every backup format the app accepts funnels through here: protobuf `.vult`,
/// encrypted protobuf, `BackupVault` JSON, bare `Vault` JSON, the old fallback
/// path and the multi-file ZIP. Before this existed only the protobuf path went
/// through the protector — `Vault.init(from: Decoder)` decodes `[KeyShare]`
/// straight off the wire — so a JSON import with a passcode set wrote
/// **plaintext shares into a protected store**, readable even while the app was
/// locked and left that way indefinitely.
///
/// Three things have to be true of an import, and they are why this is a type
/// rather than a helper:
///
/// 1. **An incoming sealed value is authenticated, not trusted.** A `.vult` or
///    JSON blob can legitimately carry a `vlt2:` string — it was exported from a
///    sealed store by a build that wrote the stored bytes — and accepting one
///    unchecked imports a share nobody can open. It is opened under the current
///    session or the import is refused. A value that opens to *another* sealed
///    value is refused outright rather than unwrapped again, for the same reason
///    ``KeyshareSweeper`` refuses it: that is adversarial input, not a share.
/// 2. **Every share is normalized under the protection state at the moment it is
///    stored** — sealed if a passcode is set, plaintext if not — so an imported
///    vault lands on the same side of the invariant as everything already there.
/// 3. **The insert and its `save()` happen inside one episode lease.** Leaving
///    the insert to an autosave puts it outside any span a passcode transition
///    can be excluded from, which is exactly how a share ends up computed under
///    one protection state and persisted under another.
///
/// > Note: the lease brackets normalize → insert → save rather than decode →
/// > insert → save. Decoding is separated from committing by a password prompt on
/// > the multi-file path, and a lease held across a modal is a lease that leaks
/// > when the user walks away — which blocks every passcode change until the app
/// > is relaunched. Re-normalizing at commit time under the lease gives the same
/// > guarantee without that failure mode: whatever the state was at decode, what
/// > reaches disk agrees with the state the save runs in.
///
/// The isolation is stated per method rather than on the type: everything it
/// *does* is main-actor work, because `Vault` is a main-actor-only `@Model`, but
/// the value itself is two immutable references and the view models that own one
/// name it as a default argument.
struct ProtectedVaultImporter {

    private let protector: KeyshareProtecting
    private let coordinator: KeyshareWriteCoordinator

    init(
        protector: KeyshareProtecting = KeyshareProtector.shared,
        coordinator: KeyshareWriteCoordinator = .shared
    ) {
        self.protector = protector
        self.coordinator = coordinator
    }

    /// Refuses a backup carrying a share this device cannot open, before the
    /// user is told anything about it.
    ///
    /// Separate from ``commit(_:into:)`` only so a bad file fails at the point
    /// it is read rather than after a password prompt and a vault picker; the
    /// commit re-checks everything it does here.
    @MainActor
    func validate(_ vault: Vault) throws {
        for share in vault.keyshares where protector.isSealed(share.keyshare) {
            _ = try openedShare(share.keyshare, pubkey: share.pubkey)
        }
    }

    /// Normalizes every share, inserts, and saves — all inside one episode lease.
    ///
    /// Two phases, like the sweep: every share of every vault is normalized and
    /// verified before a single vault is inserted, so a bad share in the third
    /// file of a ZIP does not leave the first two half-imported.
    ///
    /// - Parameter prepare: run per vault inside the lease, once the vault is
    ///   provably stored. Anything that touches the context on a vault's behalf
    ///   — default coins are the case that exists — belongs here rather than at
    ///   the call site: done before, it leaves rows behind when the import is
    ///   refused, and the token discovery it starts is unstructured work that
    ///   outlives this call and must never be aimed at a vault that could still
    ///   be withdrawn.
    @MainActor
    func commit(
        _ vaults: [Vault],
        into context: ModelContext,
        prepare: (Vault) -> Void = { _ in }
    ) throws {
        // Nothing to do is not a reason to save: an all-duplicate ZIP would
        // otherwise flush whatever unrelated work the context is carrying.
        guard !vaults.isEmpty else { return }

        guard let episode = coordinator.beginEpisode() else {
            logger.warning("Vault import refused: a passcode transition is in progress")
            throw ProtectedVaultImportError.busy
        }
        defer { coordinator.end(episode) }

        let normalized = try vaults.map { try normalizedShares(of: $0) }

        // Whatever the context was already carrying decides how a failure is
        // undone below, and it has to be sampled before anything is inserted.
        let wasCarryingOtherWork = context.hasChanges

        for (vault, shares) in zip(vaults, normalized) {
            // Whole-array assignment, never element assignment: assigning into
            // an element is not a dependable way to mark a `@Model` dirty.
            vault.keyshares = shares
            context.insert(vault)
        }

        do {
            try context.save()
        } catch {
            withdraw(vaults, from: context, rollingBack: !wasCarryingOtherWork)
            logger.error("Vault import failed to save: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Only now, over vaults that are provably on disk, and still inside the
        // lease so the rows land before a transition can begin. A failure here
        // is not an import failure: the vaults are stored and openable, and
        // their default coins are derived state that any later launch rebuilds.
        vaults.forEach(prepare)
        do {
            try context.save()
        } catch {
            logger.error("Imported vaults were stored but their default coins were not: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Privates

    /// Undoes a failed import without taking anybody else's work with it.
    ///
    /// `rollback()` discards *every* pending change in the context, and episodes
    /// deliberately overlap — a keygen can be part-way through its own writes
    /// while an import runs. So it is only used when the context was clean on
    /// the way in and the pending changes are provably ours; otherwise the
    /// imported vaults are withdrawn one by one and the rest is left alone.
    @MainActor
    private func withdraw(_ vaults: [Vault], from context: ModelContext, rollingBack: Bool) {
        guard !rollingBack else {
            context.rollback()
            return
        }
        for vault in vaults {
            context.delete(vault)
        }
    }

    @MainActor
    private func normalizedShares(of vault: Vault) throws -> [KeyShare] {
        try vault.keyshares.map { share in
            let plaintext = protector.isSealed(share.keyshare)
                ? try openedShare(share.keyshare, pubkey: share.pubkey)
                : share.keyshare

            // A passthrough with no passcode set, which is what keeps an
            // unprotected install byte-identical to one without this feature.
            return KeyShare(
                pubkey: share.pubkey,
                keyshare: try protector.seal(plaintext),
                keyId: share.keyId
            )
        }
    }

    private func openedShare(_ stored: String, pubkey: String) throws -> String {
        let opened: String
        do {
            opened = try protector.open(stored)
        } catch {
            logger.error("An imported key share could not be opened: \(String(describing: error), privacy: .public)")
            throw ProtectedVaultImportError.unreadableShare(pubkey: pubkey)
        }

        guard !protector.isSealed(opened) else {
            logger.error("An imported key share opened to another sealed value; refusing to treat it as a share")
            throw ProtectedVaultImportError.unreadableShare(pubkey: pubkey)
        }
        return opened
    }
}
