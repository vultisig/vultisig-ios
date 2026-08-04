//
//  KeyshareSweeper.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftData

private let logger = Log.app.store

enum KeyshareSweeperError: Error, Equatable {
    /// The store could not be reached at all.
    case missingModelContext
    /// The main context is carrying somebody else's unsaved work.
    case busy
    /// A share did not survive its round trip, or an already-sealed value could
    /// not be opened. Carries the share's public key so the log names it.
    case verificationFailed(pubkey: String)
}

/// Moves every stored key share to the side of the invariant the passcode is on.
///
/// A share is sealed if and only if a passcode is currently set, so setting a
/// passcode has to seal every share and removing one has to open every share.
/// This is the only thing in the feature that rewrites key material, and a
/// mistake here is lost funds rather than a bad screen.
///
/// `PasscodeService` is an `actor` and `Vault` is a SwiftData `@Model` that may
/// only be touched on the main actor, so the sweep is main-actor work behind
/// this protocol and is injected rather than reached for.
///
/// The isolation is stated **per requirement** rather than on the protocol.
/// Attributing the protocol would infer main-actor isolation onto the whole
/// conforming type, singleton included — and the actor that injects one has to
/// name that singleton as a default argument, which no `await` can reach.
protocol KeyshareSweeping {
    /// Seals every plaintext share **and authenticates every already-sealed
    /// one**. See ``KeyshareSweeper`` for why the second half is not optional.
    @MainActor func sealAll() throws

    /// Opens every sealed share back to plaintext. The GCM tag check inside
    /// `open` *is* the verification here — a successful open is proof that the
    /// value was sealed under the key in hand.
    @MainActor func unsealAll() throws

    /// Whether any stored share is already sealed.
    ///
    /// Asked before a fresh data key is minted, and it is the last guard against
    /// the worst outcome this feature has: a sealed share with no readable
    /// wrapper means a key already exists somewhere, and a replacement opens
    /// none of the ciphertext the original produced. A `Bool` is the right
    /// answer here — unlike a plaintext/sealed *census*, this asks a question
    /// about the stored form rather than about whether a value verifies.
    ///
    /// - Throws: when the store cannot be read, **including when it is carrying
    ///   unsaved work**. Not knowing must never be mistaken for "nothing is
    ///   sealed": a pending edit or deletion can hide a share that is still
    ///   sealed on disk, and the answer is used to license minting a key.
    @MainActor func hasSealedShare() throws -> Bool
}

/// The sweep, in two phases over a context nobody else is using.
///
/// Four rules, and each one is a failure someone has already had:
///
/// 1. **Two phases.** Everything is computed and verified in memory before a
///    single model is touched. Applying a vault as soon as it verifies leaves
///    earlier vaults mutated in the live context when a later one fails, and an
///    unrelated save would flush that half-swept state to disk.
/// 2. **Whole-array assignment.** `vault.keyshares = newArray`, never
///    `keyshares[i] = …` — assigning into an element is not a dependable way to
///    mark a `@Model` dirty, and a sweep that reported success while persisting
///    nothing leaves plaintext shares sitting behind a passcode.
/// 3. **Save, and `rollback()` if the save fails**, so the context cannot carry
///    a partial sweep forward.
/// 4. **Already-sealed values are opened before they are accepted, and what
///    comes out has to be a share.** `KeyshareProtector.seal` returns an
///    already-sealed value *unchanged and unauthenticated*, so a sweep that took
///    it on trust would report success over a share sealed under a key nobody
///    holds any more — a dead vault, and nothing ever revisits it because the
///    sweep said it was fine. A value that opens to *another* sealed value is
///    refused outright rather than unwrapped again.
///
/// **The context has to be clean.** Flushing foreign pending changes would
/// commit somebody's half-finished keygen, reshare or import merely because the
/// user enabled a passcode, and some code defers persistence deliberately until
/// a flow is confirmed; rolling them back would throw that work away instead.
/// Neither is this type's to do, so a dirty context is `.busy` and the user
/// retries. Autosave — on by default — is suspended for the transaction, since
/// phase two dirties every swept vault at once and only the explicit save that
/// follows may write them.
///
/// **The isolation is on the methods, not on the type.** All of the *work* is
/// main-actor work, but the value itself is two immutable references, and
/// `PasscodeService` is an `actor` that has to hold one as a stored property —
/// which a main-actor-isolated singleton could not be handed to without a hop
/// in the middle of its initializer.
final class KeyshareSweeper: KeyshareSweeping {

    static let shared = KeyshareSweeper()

    private let protector: KeyshareProtecting
    private let context: () -> ModelContext?

    init(
        protector: KeyshareProtecting = KeyshareProtector.shared,
        context: @escaping () -> ModelContext? = { Storage.shared.modelContext }
    ) {
        self.protector = protector
        self.context = context
    }

    @MainActor
    func hasSealedShare() throws -> Bool {
        guard let context = context() else {
            throw KeyshareSweeperError.missingModelContext
        }

        // The same refusal `sweep` makes, and for a sharper reason. A fetch
        // answers from the context's *pending* state, so an unsaved edit or an
        // uncommitted deletion can present a vault as plaintext — or not at all
        // — while the durable row is still sealed. This answer licenses minting
        // a fresh data key, and a key minted over a sealed share that then comes
        // back from disk opens nothing.
        guard !context.hasChanges else {
            logger.warning("Sealed-share scan refused: the store has unsaved changes")
            throw KeyshareSweeperError.busy
        }

        return try context.fetch(FetchDescriptor<Vault>())
            .contains { vault in
                vault.keyshares.contains { protector.isSealed($0.keyshare) }
            }
    }

    @MainActor
    func sealAll() throws {
        try sweep(describedAs: "seal") { stored in
            guard !self.protector.isSealed(stored) else {
                // Rule 4. Opening it is the only way to know the key in hand is
                // the key it was sealed under.
                try self.openedShare(from: stored)
                return nil
            }

            let sealed = try self.protector.seal(stored)

            // `seal` is a passthrough when no key is held, so a sweep with
            // nothing to seal with would otherwise report success over shares it
            // left in the clear.
            guard self.protector.isSealed(sealed) else {
                logger.error("Sealing produced a plaintext value — no data key is in hand")
                throw SweepFailure.unverified
            }
            guard try self.protector.open(sealed) == stored else {
                logger.error("A sealed key share did not open back to its original value")
                throw SweepFailure.unverified
            }
            return sealed
        }
    }

    @MainActor
    func unsealAll() throws {
        try sweep(describedAs: "unseal") { stored in
            guard self.protector.isSealed(stored) else { return nil }
            return try self.openedShare(from: stored)
        }
    }
}

// MARK: - Privates

private extension KeyshareSweeper {

    /// Raised by a transform to mean "this share did not verify"; the caller
    /// attaches the public key.
    enum SweepFailure: Error {
        case unverified
    }

    /// The plaintext share inside a sealed value, refusing anything that is
    /// *still* sealed once opened.
    ///
    /// A value that opens to another sealed value is an envelope wrapped around
    /// an envelope, not a share. Nothing here produces one — `seal` will not
    /// seal an already-sealed value — but an imported `.vult` or JSON backup can
    /// carry whatever bytes it likes, and unwrapping only the outer layer would
    /// write `vlt2:` back to disk while reporting the store fully unsealed. The
    /// disable that follows then deletes the key, and what is left cannot be
    /// opened by anything, ever. Unwrapping recursively is not the answer: it
    /// would accept adversarial input rather than reject it.
    @discardableResult
    func openedShare(from stored: String) throws -> String {
        let opened = try protector.open(stored)
        guard !protector.isSealed(opened) else {
            logger.error("A key share opened to another sealed value; refusing to treat it as a share")
            throw SweepFailure.unverified
        }
        return opened
    }

    /// - Parameter transform: the new value for a share's stored bytes, or
    ///   `nil` to leave the share exactly as it is.
    @MainActor
    func sweep(describedAs operation: String, _ transform: (String) throws -> String?) throws {
        guard let context = context() else {
            throw KeyshareSweeperError.missingModelContext
        }

        guard !context.hasChanges else {
            logger.warning("Key-share \(operation, privacy: .public) refused: the store has unsaved changes")
            throw KeyshareSweeperError.busy
        }

        let wasAutosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = wasAutosaveEnabled }

        // Phase one — compute and verify everything, mutating nothing.
        var pending: [(vault: Vault, shares: [KeyShare])] = []
        for vault in try context.fetch(FetchDescriptor<Vault>()) {
            if let shares = try rewrittenShares(of: vault, transform) {
                pending.append((vault, shares))
            }
        }

        guard !pending.isEmpty else {
            logger.info("Nothing to \(operation, privacy: .public)")
            return
        }

        // Phase two — every share across every vault has been proved
        // recoverable, so the writes go in together.
        for entry in pending {
            entry.vault.keyshares = entry.shares
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Key-share \(operation, privacy: .public) failed to save, rolled back: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let count = pending.reduce(0) { $0 + $1.shares.count }
        logger.info("Swept \(count, privacy: .public) key shares across \(pending.count, privacy: .public) vaults (\(operation, privacy: .public))")
    }

    /// The vault's shares after the transform, or `nil` when none of them
    /// changed. Builds a whole array for the caller to assign through the
    /// property setter — see rule 2.
    @MainActor
    func rewrittenShares(of vault: Vault, _ transform: (String) throws -> String?) throws -> [KeyShare]? {
        var result: [KeyShare] = []
        var changed = false

        for share in vault.keyshares {
            let rewritten: String?
            do {
                rewritten = try transform(share.keyshare)
            } catch {
                logger.error("A key share did not verify: \(String(describing: error), privacy: .public)")
                throw KeyshareSweeperError.verificationFailed(pubkey: share.pubkey)
            }

            guard let rewritten else {
                result.append(share)
                continue
            }
            result.append(KeyShare(pubkey: share.pubkey, keyshare: rewritten, keyId: share.keyId))
            changed = true
        }

        return changed ? result : nil
    }
}
