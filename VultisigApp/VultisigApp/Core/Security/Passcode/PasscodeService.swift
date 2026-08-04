//
//  PasscodeService.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import OSLog

private let logger = Log.app.store

enum PasscodeError: Error, Equatable {
    case wrongPasscode
    case notSet
    case alreadySet
    case lockedOut(remaining: TimeInterval)
    case invalidLength
    /// The stored wrapped key is unreadable. Distinct from a wrong passcode:
    /// no amount of retrying fixes it, and it must not be counted as a guess.
    case storageFailure
    /// A partial state change could not be completed or rolled back.
    case inconsistentState
    /// The app locked while the passcode was being verified. The passcode was
    /// not necessarily wrong; the unlock simply no longer applies.
    case cancelledByLock
    /// Another passcode transition, key-share write or vault-creation episode
    /// is in flight, or the store is carrying somebody else's unsaved work.
    /// Retryable, and the honest answer: the alternative is a settings toggle
    /// that appears to hang while a keygen finishes.
    case busy
    /// A stored key share is already sealed while no wrapped key can be read.
    /// Minting a fresh data key over that would orphan it permanently, so the
    /// set is refused rather than completed.
    case sealedSharesWithoutKey
}

/// Sets, changes, removes and verifies the app passcode.
///
/// Every operation here moves 32 bytes. The passcode wraps the data key; it does
/// not encrypt key shares, so changing or removing it rewraps that one small blob
/// and leaves every share on disk exactly as it was. The desktop client re-encrypts
/// every share of every vault on each of these operations, which puts a full
/// rewrite of key material behind a routine settings toggle.
///
/// An `actor` because these are read-modify-write sequences over shared Keychain
/// state. Concurrent failed unlocks could otherwise each read the same attempt
/// count and collapse a burst of guesses into one recorded failure, which is the
/// throttle this feature depends on.
///
/// An actor is not enough on its own, though, and that is what the transition
/// lease is for: actors are reentrant at every `await`, and both of the
/// operations below suspend across key derivation. Two callers could otherwise
/// clear their own preconditions and interleave, and a key-share write landing
/// mid-transition could persist a value computed under the other protection
/// state. Every transition therefore takes ``KeyshareWriteCoordinator``'s
/// exclusive lease **before its first `await`**.
actor PasscodeService {

    static let shared = PasscodeService()

    static let passcodeLength = 5

    private let keyStore: KeyshareKeyStoring
    private let session: KeyshareKeySession
    private let lockService: AppLockService
    private let limiter: PasscodeAttemptLimiting
    private let coordinator: KeyshareWriteCoordinator
    private let sweeper: KeyshareSweeping

    init(
        keyStore: KeyshareKeyStoring = DefaultKeyshareKeyStore.shared,
        session: KeyshareKeySession = .shared,
        lockService: AppLockService = .shared,
        limiter: PasscodeAttemptLimiting = PasscodeAttemptLimiter(),
        coordinator: KeyshareWriteCoordinator = .shared,
        sweeper: KeyshareSweeping = KeyshareSweeper.shared
    ) {
        self.keyStore = keyStore
        self.session = session
        self.lockService = lockService
        self.limiter = limiter
        self.coordinator = coordinator
        self.sweeper = sweeper
    }

    /// Fails closed. An unreadable Keychain may well hold a wrapped key, and the
    /// one thing that must never happen is a fresh data key being minted over an
    /// existing one — a new key opens none of the shares the old one sealed, so
    /// every vault on the device would be gone. Refusing to set a passcode
    /// because the Keychain is momentarily unreadable costs a retry.
    var isSet: Bool {
        switch keyStore.loadWrappedDataKey() {
        case .present, .unavailable:
            return true
        case .absent:
            return false
        }
    }

    // MARK: - Set

    /// Mints a data key, puts it behind the passcode, and seals every stored
    /// share under it.
    ///
    /// The order below is the whole design, and each step sits where it does to
    /// close a specific way of losing key material:
    ///
    /// - the **wrapper is durable before anything is sealed**. Mint, sweep, then
    ///   store would orphan every sealed share if the process died in between,
    ///   because the key only ever lived in memory;
    /// - the **mode switches the moment the wrapper verifies**, not at the end.
    ///   With it at the end, a failed sweep left a durable wrapper behind
    ///   `.deviceAuth`: the retry failed `alreadySet`, and the resume that would
    ///   have finished the job only runs on a passcode unlock the mode would
    ///   never present — a passcode both durable and unreachable;
    /// - a **failed sweep does not delete the wrapper**. Sealing may already
    ///   have begun, and a wrapper deleted over half-sealed shares strands them:
    ///   a later set mints a *different* key, which opens none of that
    ///   ciphertext. The app stays in the pending-passcode state instead, and
    ///   the next unlock's resume finishes it.
    func setPasscode(_ passcode: String) async throws {
        let lease = try beginTransition()
        defer { coordinator.end(lease) }

        // Read first, before anything else in this method. A background `lock()`
        // is `nonisolated` and stays outside the coordinator on purpose — it
        // must never block on a transition — so it can land at any point from
        // here on, and `adopt(_:ifGeneration:)` at the end is how it wins.
        // Reading this any later would silently undo a lock that landed in
        // between, leaving the key live in memory behind a lock screen. The
        // window cannot be closed entirely while `lock()` is deliberately
        // unsynchronized; it can be made as small as the first instruction.
        let generation = session.currentGeneration

        try validate(passcode)
        guard !isSet else { throw PasscodeError.alreadySet }

        // Never mint over evidence. A sealed share with no readable wrapper
        // means a key already exists somewhere, and the one generated below
        // opens none of what it sealed. A *completed* disable leaves nothing
        // sealed, so re-enabling still works; an *interrupted* set leaves a
        // wrapper, so `isSet` above refuses first and resume — not a fresh
        // mint — is the recovery.
        guard try await !storeHoldsASealedShare() else {
            throw PasscodeError.sealedSharesWithoutKey
        }

        let dataKey = try keyStore.generateDataKey()

        let wrapped = try await keyStore.wrap(dataKey, passcode: passcode)
        try keyStore.storeWrappedDataKey(wrapped)

        lockService.mode = .passcode

        guard session.adopt(dataKey, ifGeneration: generation) else {
            // A lock landed mid-derivation. The wrapper is durable and the gate
            // is up, so the app is in the pending-passcode state and the next
            // unlock seals what this call did not.
            throw PasscodeError.cancelledByLock
        }

        try await sealEverything()

        limiter.recordSuccess()
    }

    // MARK: - Unlock

    @discardableResult
    func unlock(with passcode: String, now: Date = Date()) async throws -> SymmetricKey {
        // First instruction, for the same reason it is in `setPasscode`: a
        // `nonisolated` lock() can land during the Keychain read below as easily
        // as during the derivation, and a generation read afterwards would let
        // the adopt undo it.
        let generation = session.currentGeneration

        let lockout = limiter.remainingLockout(now: now)
        guard lockout <= 0 else {
            throw PasscodeError.lockedOut(remaining: lockout)
        }

        let wrapped: Data
        switch keyStore.loadWrappedDataKey() {
        case .present(let blob):
            wrapped = blob
        case .absent:
            throw PasscodeError.notSet
        case .unavailable:
            // Not "there is no passcode". The item may be there and momentarily
            // unreadable, and `notSet` is what sends the UI off to offer setting
            // one — over the top of a wrapper that still exists.
            throw PasscodeError.storageFailure
        }

        do {
            let dataKey = try await keyStore.unwrap(wrapped, passcode: passcode)

            // A lock landed while the derivation was running. Returning the key
            // anyway would let the caller — change or disable — carry on and
            // adopt it, undoing that lock by the back door.
            guard session.adopt(dataKey, ifGeneration: generation) else {
                throw PasscodeError.cancelledByLock
            }

            limiter.recordSuccess()
            return dataKey
        } catch KeyshareKeyStoreError.malformedWrappedKey {
            // Not a guess. Counting it would bury an unrecoverable storage
            // problem under a growing lockout and tell the user the wrong thing.
            throw PasscodeError.storageFailure
        } catch PasscodeError.cancelledByLock {
            // Not a guess: the passcode may well have been right.
            throw PasscodeError.cancelledByLock
        } catch {
            // If the failure cannot be recorded there is no throttle, so refuse
            // the attempt rather than let an uncounted guess through.
            try limiter.recordFailure(now: now)
            throw PasscodeError.wrongPasscode
        }
    }

    /// Forgets the data key. Sealed shares become unreadable until the next
    /// unlock, which is the point — a locked app cannot sign.
    ///
    /// `nonisolated` because it touches no actor state and is called from
    /// scene-phase hooks; `KeyshareKeySession` does its own locking.
    nonisolated func lock() {
        session.clear()
    }

    // MARK: - Change

    /// Rewraps the same data key under a new passcode. **No key share is read or
    /// written**, which is what makes this safe to do casually.
    ///
    /// It still takes the transition lease: it rewrites the one item every
    /// sealed share depends on, and interleaving with a set or a disable is how
    /// the wrapper ends up holding a key that matches nothing on disk.
    func changePasscode(current: String, new: String, now: Date = Date()) async throws {
        let lease = try beginTransition()
        defer { coordinator.end(lease) }

        try validate(new)

        let dataKey = try await unlock(with: current, now: now)
        let rewrapped = try await keyStore.wrap(dataKey, passcode: new)
        try keyStore.storeWrappedDataKey(rewrapped)
    }

    // MARK: - Disable

    /// The exact inverse of ``setPasscode(_:)``: opens every share back to
    /// plaintext and removes the wrapped key, leaving the device
    /// byte-for-byte in the state it would have been in had a passcode never
    /// been set.
    ///
    /// Two orderings carry the weight:
    ///
    /// - **the mode changes before the wrapper is deleted.** With the reverse
    ///   order, a crash after the deletion but before the mode change leaves
    ///   plaintext shares behind `.passcode` and no wrapper to unlock against —
    ///   a gate that can never open. The smaller window this creates (plaintext
    ///   shares, wrapper present, `.deviceAuth` persisted) is the one launch
    ///   reconciliation already repairs;
    /// - **anything else holding a copy of the data key goes first**, before a
    ///   single share moves. A biometric copy of the key is the case that
    ///   exists: it holds the *same* key, so a survivor would quietly work again
    ///   the next time a passcode was set, and failing to remove it after the
    ///   shares had already been opened would report an error over a passcode
    ///   that was half gone. Nothing has changed yet at that point, so aborting
    ///   there is clean.
    ///
    /// If the deletion fails there is one protocol, not a choice: prove the
    /// wrapper is durable, restore `.passcode`, reseal transactionally, throw.
    /// The app is back to a working passcode and the user retries. Proving the
    /// wrapper first is not belt and braces — `deleteWrappedDataKey` reports
    /// failure on an *unreadable* read-back too, so "it threw" does not mean
    /// "the item is still there", and resealing over a wrapper that is in fact
    /// gone would leave ciphertext whose only key is in memory until the next
    /// lock.
    func disablePasscode(current: String, now: Date = Date()) async throws {
        let lease = try beginTransition()
        defer { coordinator.end(lease) }

        _ = try await unlock(with: current, now: now)

        // The exact bytes, kept for the rollback below. `unlock` has just proved
        // they open, so this is the one moment they are known good.
        let wrapped = keyStore.loadWrappedDataKey().valueTreatingUnavailableAsAbsent

        // The GCM tag check inside every open is the verification: a share that
        // comes back out is provably recoverable, and the key is still in hand
        // if the rest of this has to be undone.
        try await unsealEverything()

        lockService.mode = .deviceAuth

        do {
            try keyStore.deleteWrappedDataKey()
        } catch {
            try await restorePasscodeAfterFailedRemoval(wrapped: wrapped)
            throw error
        }

        // Nothing is sealed any more, so the key has no further use. Clearing
        // also bumps the session generation, which invalidates the resume latch.
        session.clear()
    }

    /// Puts the passcode back after a wrapper deletion that reported failure.
    ///
    /// The wrapper is re-stored — and therefore read-back-verified — *before* a
    /// single share is resealed, because a deletion that threw may still have
    /// removed the item. If it cannot be made durable, nothing is resealed:
    /// plaintext shares with no key anywhere is precisely the no-passcode
    /// resting state, and it is the only outcome here that loses nothing.
    private func restorePasscodeAfterFailedRemoval(wrapped: Data?) async throws {
        do {
            guard let wrapped else { throw PasscodeError.inconsistentState }
            try keyStore.storeWrappedDataKey(wrapped)
        } catch {
            // No provable wrapper, so the key in memory must go with it.
            // Leaving it cached would let a keygen or a reshare seal a *new*
            // share against a key nothing on disk wraps, and the first lock
            // after that makes the share unreadable forever.
            session.clear()
            logger.error("Could not restore the wrapped key after a failed passcode removal: \(String(describing: error), privacy: .public)")
            throw PasscodeError.inconsistentState
        }

        lockService.mode = .passcode

        do {
            try await sealEverything()
        } catch {
            // Plaintext shares behind a live passcode: weaker than where this
            // started, but nothing is lost — the wrapper is provably there, so
            // the next unlock's resume seals them.
            logger.error("Could not reseal after a failed passcode removal: \(String(describing: error), privacy: .public)")
            throw PasscodeError.inconsistentState
        }
    }

    // MARK: - Helpers

    /// Claims the coordinator for one transition, mapping contention onto the
    /// service's own vocabulary.
    ///
    /// Contention is reported rather than queued: a passcode change that waits
    /// silently for a keygen to finish looks like a hang, and "finish creating
    /// your vault first" is the honest version of the guarantee.
    private func beginTransition() throws -> TransitionLease {
        do {
            return try coordinator.beginTransition()
        } catch {
            throw PasscodeError.busy
        }
    }

    private func storeHoldsASealedShare() async throws -> Bool {
        do {
            return try await sweeper.hasSealedShare()
        } catch KeyshareSweeperError.busy {
            throw PasscodeError.busy
        }
    }

    private func sealEverything() async throws {
        do {
            try await sweeper.sealAll()
        } catch KeyshareSweeperError.busy {
            throw PasscodeError.busy
        }
    }

    private func unsealEverything() async throws {
        do {
            try await sweeper.unsealAll()
        } catch KeyshareSweeperError.busy {
            throw PasscodeError.busy
        }
    }

    private func validate(_ passcode: String) throws {
        guard passcode.count == Self.passcodeLength,
              passcode.allSatisfy(\.isNumber) else {
            throw PasscodeError.invalidLength
        }
    }
}
