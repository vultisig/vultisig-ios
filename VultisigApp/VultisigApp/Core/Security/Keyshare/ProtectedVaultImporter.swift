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
///    That is ``KeyshareNormalizer``'s job, shared with the keygen commit, which
///    holds its shares across an interval with the same shape.
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

    private let normalizer: KeyshareNormalizer
    private let coordinator: KeyshareWriteCoordinator
    private let save: @MainActor (ModelContext) throws -> Void

    /// - Parameter save: the store write. A seam, and only a seam: SwiftData
    ///   offers no way to make an in-memory `save()` fail on demand, and the
    ///   paths that matter most here are the ones a save failure opens.
    init(
        protector: KeyshareProtecting = KeyshareProtector.shared,
        coordinator: KeyshareWriteCoordinator = .shared,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.normalizer = KeyshareNormalizer(protector: protector)
        self.coordinator = coordinator
        self.save = save
    }

    /// Refuses a backup carrying a share this device cannot open, before the
    /// user is told anything about it.
    ///
    /// Separate from ``commit(_:into:)`` only so a bad file fails at the point
    /// it is read rather than after a password prompt and a vault picker; the
    /// commit re-checks everything it does here.
    @MainActor
    func validate(_ vault: Vault) throws {
        try statedAsAnImportFailure { try normalizer.verify(vault) }
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
    ///   the call site, where it would leave rows behind when the import is
    ///   refused. It answers whether it did its work, and must be idempotent: a
    ///   vault it leaves unprepared is put through it again, against a context
    ///   the failed attempt has been withdrawn from.
    ///
    ///   It must not *start* work that outlives it. Token discovery is the case
    ///   that exists, and it is aimed at rows this method can still take back —
    ///   so the caller starts it once `commit` has returned, never from inside
    ///   `prepare`.
    @MainActor
    func commit(
        _ vaults: [Vault],
        into context: ModelContext,
        prepare: (Vault) -> Bool = { _ in true }
    ) throws {
        // Nothing to do is not a reason to save: an all-duplicate ZIP would
        // otherwise flush whatever unrelated work the context is carrying.
        guard !vaults.isEmpty else { return }

        guard let episode = coordinator.beginEpisode() else {
            logger.warning("Vault import refused: a passcode transition is in progress")
            throw ProtectedVaultImportError.busy
        }
        defer { coordinator.end(episode) }

        let normalized = try statedAsAnImportFailure {
            try vaults.map { try normalizer.normalizedShares(of: $0) }
        }

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
            try save(context)
        } catch {
            withdraw(vaults, from: context, rollingBack: !wasCarryingOtherWork)
            logger.error("Vault import failed to save: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Only now, over vaults that are provably on disk, and still inside the
        // lease so the rows land before a transition can begin. A failure here
        // is not an import failure — the vaults are stored and openable, and
        // refusing an import that has already reached disk would leave the user
        // a vault they cannot re-import — so it is reported rather than thrown.
        //
        // It is checked as a postcondition and not only as a `catch`, because
        // the way this went wrong in practice was a save that *succeeded* and
        // stored nothing: the coins attached to a vault that had already been
        // saved, where that write does not take. An error-only guard saw a
        // clean import and said nothing. And nothing else rebuilds this later —
        // default coins are set at keygen and at import and nowhere else — so a
        // vault that leaves here unprepared is one the user opens on an empty
        // wallet, with no error, for good.
        var unprepared = vaultsLeftUnprepared(among: vaults, by: prepare, in: context)
        if !unprepared.isEmpty {
            // `prepare` is idempotent by contract and these vaults are brand
            // new — nothing else has touched them — so running it again is the
            // one repair available at a point where the user cannot usefully be
            // told anything. Once, not in a loop: a preparation that fails twice
            // fails for a reason a third attempt will not change.
            unprepared = vaultsLeftUnprepared(among: unprepared, by: prepare, in: context)
        }
        if !unprepared.isEmpty {
            logger.error("Imported vaults were stored without their default coins: \(unprepared.count, privacy: .public) of \(vaults.count, privacy: .public) will open missing at least one of their default chains")
        }
    }

    // MARK: - Privates

    /// Runs `prepare` over vaults that are already stored, saves what it wrote,
    /// and answers the ones that did not come out prepared.
    ///
    /// A save that throws makes every vault in the batch unprepared, whatever
    /// `prepare` said: work that is not on disk is work the next launch will not
    /// find. And what it wrote is withdrawn before answering, because a failed
    /// save leaves those inserts *pending*, not gone — the retry would run
    /// against a context still holding the first attempt's rows, and after a
    /// second failure the whole import would return with them still eligible for
    /// an autosave or for the next unrelated `save()` anywhere in the app. That
    /// is work this method has already given up on reaching disk by a route
    /// nothing here can see.
    ///
    /// `rollback()` and not a per-row withdrawal, and it is safe here in a way
    /// it is not in ``commit(_:into:prepare:)``: the insert's own save has
    /// already flushed whatever the context was carrying, so everything pending
    /// at this point was written by `prepare`.
    @MainActor
    private func vaultsLeftUnprepared(
        among vaults: [Vault],
        by prepare: (Vault) -> Bool,
        in context: ModelContext
    ) -> [Vault] {
        let unprepared = vaults.filter { !prepare($0) }
        do {
            try save(context)
        } catch {
            context.rollback()
            logger.error("Imported vaults were stored but their default coins were not: \(error.localizedDescription, privacy: .public)")
            return vaults
        }
        return unprepared
    }

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

    /// Restates a normalization failure in the import's own terms.
    ///
    /// A share that does not open is the *file's* problem, and `unreadableShare`
    /// names it. A share that cannot be sealed is the *session's* — `seal` fails
    /// only when there is no key to seal with — and the raw
    /// `KeyshareProtectionError` is what this surface has always raised for it,
    /// so it passes through unchanged. Not because a call site renders it: they
    /// all show a fixed "restore failed" string. Because the error a caller
    /// catches is part of what the import promises, and this change is not the
    /// place to renegotiate it.
    @MainActor
    private func statedAsAnImportFailure<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let failure as KeyshareNormalizationFailure {
            switch failure {
            case .unreadable(let pubkey):
                logger.error("Vault import refused: key share \(pubkey, privacy: .public) could not be opened")
                throw ProtectedVaultImportError.unreadableShare(pubkey: pubkey)
            case .unsealable(let pubkey, let underlying):
                logger.error("Vault import refused: key share \(pubkey, privacy: .public) could not be sealed")
                throw underlying
            }
        }
    }
}
