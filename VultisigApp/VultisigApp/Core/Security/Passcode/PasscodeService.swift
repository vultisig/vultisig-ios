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

    /// The session generation whose resume sweep has already run, so it runs at
    /// most once per unlocked session. `lock()` bumps the generation, and that is
    /// what resets this — there is nothing to clear, which matters because
    /// `lock()` is `nonisolated` and cannot touch actor state.
    private var resumedGeneration: Int?

    /// Set while an app unlock is in flight, and while a passcode is being
    /// verified. Neither is covered by the coordinator — an unlock takes a
    /// *write* lease, and writes do not exclude each other — and neither is
    /// covered by the actor either, because both suspend across key derivation
    /// and actors are reentrant at every `await`. Two overlapping verifications
    /// would both clear the attempt limiter's lockout check before either
    /// recorded a failure, which is the throttle switching itself off; two
    /// overlapping app unlocks would let the slower one's post-sweep generation
    /// check clear the faster one's perfectly good session.
    private var isAppUnlockInFlight = false
    private var isVerifyingPasscode = false

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

    /// Opens the app on the lock screen.
    ///
    /// Distinct from ``unlock(with:now:)``, which is passcode *verification* and
    /// is what change and disable use. This one holds the coordinator for the
    /// whole operation and finishes any sweep an earlier transition left half
    /// done before the caller is told the app is open, so the lock screen is the
    /// one place the invariant is re-established.
    ///
    /// It takes a **write** lease rather than a transition lease, and that is
    /// the difference between a recoverable app and a bricked one: a transition
    /// is refused while a vault-creation episode is open, keygen holds one
    /// through the deferred "Looks Good" commit, and an app that auto-locked on
    /// that screen could then never be unlocked — the flow cannot be finished
    /// without unlocking, and unlocking could not happen while the flow is open.
    /// A write lease excludes set, change and disable, which is all an unlock
    /// needs, and is refused by none of them.
    @discardableResult
    func unlockApp(with passcode: String, now: Date = Date()) async throws -> SymmetricKey {
        // Write leases do not exclude each other, so this is what keeps two app
        // unlocks apart. Read and set with no `await` between them, which is
        // what makes it atomic inside the actor.
        guard !isAppUnlockInFlight else { throw PasscodeError.busy }
        isAppUnlockInFlight = true
        defer { isAppUnlockInFlight = false }

        let lease = try beginUnlock()
        defer { coordinator.end(lease) }

        let generation = session.currentGeneration
        let dataKey = try await unlock(with: passcode, now: now)
        await resumeSweepUnlocked()

        // `unlock` only guards the *adoption* against a lock. A lock landing
        // during the sweep would otherwise be followed by a successful return,
        // and the caller would dismiss the lock screen over a session that is
        // locked again.
        guard session.currentGeneration == generation else {
            session.clear()
            throw PasscodeError.cancelledByLock
        }
        return dataKey
    }

    /// One rule: **with the data key in hand and a wrapper present, seal any
    /// share that is still plaintext.**
    ///
    /// That finishes an interrupted `setPasscode`, re-establishes the invariant
    /// after an interrupted `disablePasscode` (whose wrapper goes last, so an
    /// interruption leaves it present and the shares get sealed again — the user
    /// simply presses disable twice), and closes "plaintext introduced by a
    /// downgrade stays plaintext forever" as a side effect. It deliberately does
    /// *not* try to tell an interrupted disable from an interrupted set: with the
    /// wrapper present there is no way to, and guessing "disable" would silently
    /// remove protection.
    ///
    /// **Non-acquiring, and there is deliberately no acquiring variant.** Both
    /// app-unlock paths already hold a lease that excludes transitions, and an
    /// acquiring version would ask the coordinator for one from inside it — which
    /// is exactly what the coordinator refuses, so it would throw `.busy` on the
    /// single path that has to work every time.
    ///
    /// **Failures do not fail the unlock.** The key has already been adopted by
    /// the time this runs, so the session *is* open; reporting an error would
    /// leave the lock screen up over an unlocked session, and a persistent cause
    /// — an unsaved edit somewhere in the store, one share that will not open —
    /// would lock the user out of an app whose passcode they know. Shares staying
    /// plaintext for another lock cycle is the lesser failure, and the latch is
    /// only set on success, so the next unlock tries again.
    ///
    /// The latch is per unlocked session: `lock()` bumps the session generation,
    /// which is what invalidates it, so plaintext introduced after a successful
    /// sweep is picked up on the next lock cycle rather than never.
    func resumeSweepUnlocked() async {
        guard case .unlocked = session.currentState() else { return }
        guard case .present = keyStore.loadWrappedDataKey() else { return }

        let generation = session.currentGeneration
        guard resumedGeneration != generation else { return }

        do {
            try await sweeper.sealAll()
            resumedGeneration = generation
        } catch {
            logger.error("Resume sweep failed; the app stays unlocked and the next unlock retries: \(String(describing: error), privacy: .public)")
        }
    }

    /// Verifies a passcode and puts the data key back in the session.
    ///
    /// **Not the app-unlock path.** Change and disable use this to check the
    /// current passcode, so it takes no lease and runs no resume sweep. A lock
    /// screen wired to this instead of ``unlockApp(with:now:)`` would look
    /// identical and silently never finish an interrupted transition.
    @discardableResult
    func unlock(with passcode: String, now: Date = Date()) async throws -> SymmetricKey {
        // One verification at a time. The lockout is checked here and the
        // failure recorded after the derivation, so overlapping attempts would
        // all clear the check before any of them recorded anything — a burst of
        // guesses collapsing into one counted failure, which is the throttle
        // this feature depends on switching itself off.
        guard !isVerifyingPasscode else { throw PasscodeError.busy }
        isVerifyingPasscode = true
        defer { isVerifyingPasscode = false }

        // First instruction after that, for the same reason it is in
        // `setPasscode`: a `nonisolated` lock() can land during the Keychain
        // read below as easily as during the derivation, and a generation read
        // afterwards would let the adopt undo it.
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
    /// scene-phase hooks; `KeyshareKeySession` does its own locking. Bumping the
    /// session generation is also what resets the resume latch, which is why the
    /// latch is keyed on the generation rather than being a flag this would have
    /// to reach into the actor to clear.
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

    /// Refused only by another passcode transition — see ``unlockApp(with:now:)``
    /// for why an unlock must not be refused by anything else.
    private func beginUnlock() throws -> WriteLease {
        do {
            return try coordinator.beginWrite()
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
