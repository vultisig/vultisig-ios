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
/// A key share is sealed **if and only if a passcode is currently set**, so the
/// operations here split in two. `changePasscode` moves 32 bytes: the passcode
/// wraps the data key rather than the shares, so rewrapping that one small blob
/// leaves every share on disk exactly as it was — where the desktop client
/// re-encrypts every share of every vault for the same toggle. `setPasscode` and
/// `disablePasscode` are the other kind: they cross the invariant, so each one
/// does rewrite every stored share, which is why both are transactional, both
/// take the exclusive lease, and both are resumable.
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

    static let passcodeLength = 6

    private let keyStore: KeyshareKeyStoring
    private let session: KeyshareKeySession
    private let lockService: AppLockService
    private let limiter: PasscodeAttemptLimiting
    private let coordinator: KeyshareWriteCoordinator
    private let sweeper: KeyshareSweeping
    private let biometrics: BiometricUnlockStore

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
        sweeper: KeyshareSweeping = KeyshareSweeper.shared,
        biometrics: BiometricUnlockStore = .shared
    ) {
        self.keyStore = keyStore
        self.session = session
        self.lockService = lockService
        self.limiter = limiter
        self.coordinator = coordinator
        self.sweeper = sweeper
        self.biometrics = biometrics
    }

    var isBiometricUnlockEnabled: Bool {
        biometrics.isEnabled
    }

    /// Whether this device could hold the shortcut at all, so Settings can say
    /// why the switch is refusing instead of just returning it to off.
    var biometricAvailability: BiometricAvailability {
        biometrics.availability
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

    /// Whether the data key is currently held.
    ///
    /// `nonisolated` on purpose: the caller is the lock screen, deciding whether
    /// it may still come down, and it has to be able to ask without an `await`.
    /// An `await` would be a suspension point between the answer and the act,
    /// which is exactly the gap this is meant to close — `lock()` is
    /// `nonisolated` too and can land in it.
    nonisolated var isSessionUnlocked: Bool {
        if case .unlocked = session.currentState() { return true }
        return false
    }

    /// Whether a passcode gate still has a passcode behind it.
    ///
    /// A lock screen is raised from ``AppLockService/mode`` and then *held* by
    /// whatever put it up, so it is a cache of a value a transition can move
    /// underneath it — and one transition invalidates that cache in the worst
    /// possible way. A `disablePasscode` that completes while the gate is up
    /// leaves `.deviceAuth`, no wrapper, and a screen whose only exit calls
    /// ``unlockApp(with:now:)`` — which now has nothing to verify against and can
    /// only ever throw `notSet`. Nothing the user types opens it and force
    /// quitting is the only way out.
    ///
    /// So the gate is not a flag anyone may keep: it is this question, asked
    /// again. Nothing may leave a lock screen standing while this is `false`,
    /// and ``disablePasscode(current:now:)`` guarantees it is `false` by the time
    /// it returns.
    ///
    /// Only a **confirmed** absence lowers it. An unreadable Keychain leaves the
    /// gate up — the item may well be there, and taking a real gate down over a
    /// momentary read failure is the one mistake available here that removes
    /// protection rather than restoring access.
    ///
    /// `nonisolated` for the same reason ``isSessionUnlocked`` is: the caller is
    /// the lock screen, and an `await` between the answer and the act is exactly
    /// the gap this exists to close.
    nonisolated var isPasscodeGateRequired: Bool {
        guard lockService.mode == .passcode else { return false }
        if case .absent = keyStore.loadWrappedDataKey() { return false }
        return true
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
        // Literally the first statement, and ahead of the lease deliberately. A
        // background `lock()` is `nonisolated` and stays outside the coordinator
        // on purpose — it must never block on a transition — so it can land at
        // any point from here on, including while the lease is being claimed,
        // and `adopt(_:ifGeneration:)` at the end is how it wins. Reading this
        // any later would silently undo a lock that landed in between, leaving
        // the key live in memory behind a lock screen. The window cannot be
        // closed entirely while `lock()` is deliberately unsynchronized; it can
        // be made as small as the first instruction, and that is what this is.
        let generation = session.currentGeneration

        let lease = try beginTransition()
        defer { coordinator.end(lease) }

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

        // A biometric copy with no passcode behind it is a leftover — a previous
        // install's, or one a reconciliation could not clear. It is bound to a
        // wrapper that no longer exists, so it could never open the app anyway;
        // what it *can* do is report biometric unlock as already enabled for a
        // passcode the user is only now creating. Failing here is deliberate:
        // the invariant is that a copy exists only alongside the wrapper it
        // belongs to.
        if biometrics.isEnabled {
            try biometrics.disable()
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
    /// whole operation and *attempts* any sweep an earlier transition left half
    /// done before the caller is told the app is open, so the lock screen is the
    /// one place the invariant is re-established.
    ///
    /// **Attempts, not guarantees.** ``resumeSweepUnlocked()`` swallows its own
    /// failures on purpose — see its documentation — so a successful return here
    /// means the session is open, not that every share is sealed. A persistent
    /// resume failure therefore leaves plaintext shares behind a live passcode,
    /// logged and surfaced nowhere else.
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
        // First statement, ahead of the flag and the lease, for the reason
        // spelled out on `setPasscode`: `lock()` can land while either is being
        // claimed, and a generation read afterwards would not see it.
        let generation = session.currentGeneration

        // Write leases do not exclude each other, so this is what keeps two app
        // unlocks apart. Read and set with no `await` between them, which is
        // what makes it atomic inside the actor.
        guard !isAppUnlockInFlight else { throw PasscodeError.busy }
        isAppUnlockInFlight = true
        defer { isAppUnlockInFlight = false }

        let lease = try beginUnlock()
        defer { coordinator.end(lease) }

        let dataKey: SymmetricKey
        do {
            dataKey = try await unlock(with: passcode, now: now, anchoredTo: generation)
        } catch PasscodeError.notSet {
            // A gate with nothing behind it, and the user is standing in front
            // of it. `notSet` comes only from a **confirmed** absence, so this
            // is not a Keychain that went quiet: the passcode is genuinely gone
            // and no entry on this screen can ever be right. Leaving the mode at
            // `.passcode` would keep asking for it until the app is force quit,
            // so the same repair launch reconciliation performs is done here,
            // now, while somebody is actually locked out by it.
            lowerThePasscodeGateWithNothingBehindIt()
            throw PasscodeError.notSet
        }

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

    // MARK: - Biometric shortcut

    /// Opens the app on a biometric match, and is the app-unlock path in every
    /// respect the passcode one is — same in-flight guard, same **write** lease
    /// (never a transition lease: a transition is refused while a keygen episode
    /// is open, so an app that locked on the review screen could never be
    /// opened), same resume sweep, same generation check on both sides of it.
    /// Anything less and the shortcut would be a second, weaker way in.
    ///
    /// **Fails closed, and only against a confirmed-present wrapper.** `isSet`
    /// deliberately reads an *unreadable* Keychain as "set", which is right for
    /// refusing to mint a second key over an existing one and wrong here: the
    /// stored copy has to be checked against the wrapper's actual bytes, and
    /// there is nothing to check against if it cannot be read. Every other
    /// outcome — cancelled, locked out, enrolment changed, item gone, copy
    /// superseded — throws, and the passcode screen stays where it is.
    ///
    /// The biometric read is synchronous and blocks the actor while the system
    /// prompt is up. That is the same shape the passcode path has while deriving
    /// a key, and it is what keeps the generation capture genuinely ahead of
    /// every suspension point in this method.
    @discardableResult
    func unlockWithBiometrics(reason: String) async throws -> SymmetricKey {
        // First statement, exactly as `setPasscode`, `changePasscode`,
        // `disablePasscode` and `unlockApp` read it. `lock()` is `nonisolated`
        // and synchronizes with nothing, so it can land while the in-flight flag
        // and the lease are being claimed — and a generation read after that
        // would not see it, leaving `adopt` free to succeed and quietly undo the
        // lock. It was read below the lease here alone.
        let generation = session.currentGeneration

        guard !isAppUnlockInFlight else { throw PasscodeError.busy }
        isAppUnlockInFlight = true
        defer { isAppUnlockInFlight = false }

        let lease = try beginUnlock()
        defer { coordinator.end(lease) }

        let wrapped: Data
        switch keyStore.loadWrappedDataKey() {
        case .present(let blob):
            wrapped = blob
        case .absent:
            throw PasscodeError.notSet
        case .unavailable:
            throw PasscodeError.storageFailure
        }

        let dataKey = try biometrics.unlock(reason: reason, boundTo: wrapped)

        guard session.adopt(dataKey, ifGeneration: generation) else {
            throw PasscodeError.cancelledByLock
        }
        // A biometric match is a successful authentication, so it clears the
        // passcode throttle exactly as a correct passcode does.
        limiter.recordSuccess()

        await resumeSweepUnlocked()

        guard session.currentGeneration == generation else {
            session.clear()
            throw PasscodeError.cancelledByLock
        }
        return dataKey
    }

    /// Stores a biometry-guarded copy of the data key, bound to the wrapper it
    /// belongs to. Requires the app to be unlocked, since it never unwraps
    /// anything itself.
    ///
    /// Takes a write lease: it writes a copy of the key that a concurrent
    /// `disablePasscode` is in the middle of removing, and a copy created after
    /// that removal is precisely the orphan the binding exists to catch. A write
    /// lease excludes every transition, which is all this needs.
    func enableBiometricUnlock() throws {
        let lease = try beginBiometricWrite()
        defer { coordinator.end(lease) }

        let wrapped: Data
        switch keyStore.loadWrappedDataKey() {
        case .present(let blob):
            wrapped = blob
        case .absent:
            throw PasscodeError.notSet
        case .unavailable:
            throw PasscodeError.storageFailure
        }

        let generation = session.currentGeneration
        guard case .unlocked(let dataKey) = session.currentState() else {
            throw PasscodeError.cancelledByLock
        }

        try biometrics.enable(dataKey: dataKey, boundTo: wrapped)

        // A lock can land between reading the key and storing it. Storing a
        // shortcut for a session the user has since locked would enable one they
        // never completed, so it is undone.
        guard session.currentGeneration == generation else {
            do {
                try biometrics.disable()
            } catch {
                // The copy survived the rollback. Reporting only "cancelled"
                // would leave a working shortcut behind that the UI believes
                // does not exist.
                throw PasscodeError.inconsistentState
            }
            throw PasscodeError.cancelledByLock
        }
    }

    /// Puts back the biometric copy a disable removed before deciding it was not
    /// going to finish.
    ///
    /// Best effort by construction, and it says so rather than throwing: the
    /// caller is already on its way out with a more important error, and
    /// replacing that error with this one would hide why the disable stopped.
    /// Every failure to restore is logged, and the worst case is an optional
    /// shortcut the user has to turn on again — never a share that cannot be
    /// opened.
    private func restoreBiometricCopyAfterAbort(
        _ dataKey: SymmetricKey,
        boundTo wrapped: Data?,
        existed: Bool
    ) {
        guard existed else { return }

        guard let wrapped else {
            logger.error("A disable aborted after removing the biometric copy and the wrapper it was bound to is unreadable; the shortcut is off")
            return
        }

        do {
            try biometrics.enable(dataKey: dataKey, boundTo: wrapped)
        } catch {
            logger.error("Could not restore the biometric copy after an aborted disable: \(String(describing: error), privacy: .public)")
        }
    }

    func disableBiometricUnlock() throws {
        let lease = try beginBiometricWrite()
        defer { coordinator.end(lease) }

        try biometrics.disable()
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
        // The argument is evaluated first, so this reads the generation as the
        // first thing this call does. Nothing ran before it, so the generation
        // as it stands here *is* the generation this operation started at.
        try await unlock(with: passcode, now: now, anchoredTo: session.currentGeneration)
    }

    /// The verification, anchored to the session generation its **caller**
    /// observed as that caller's own first act.
    ///
    /// There is no variant that reads the generation for itself, and that is the
    /// point. `changePasscode`, `disablePasscode` and `unlockApp` are already
    /// under way by the time they reach here, and `lock()` is `nonisolated` and
    /// synchronizes with nothing — so a lock landing in between would be
    /// invisible to a generation read at this depth, the adopt below would
    /// succeed, and the lock would be undone by the back door. For the disable
    /// that is worse than a lost lock: it goes on to remove the very passcode
    /// the lock screen is waiting for.
    private func unlock(with passcode: String, now: Date, anchoredTo generation: Int) async throws -> SymmetricKey {
        // One verification at a time. The lockout is checked here and the
        // failure recorded after the derivation, so overlapping attempts would
        // all clear the check before any of them recorded anything — a burst of
        // guesses collapsing into one counted failure, which is the throttle
        // this feature depends on switching itself off.
        guard !isVerifyingPasscode else { throw PasscodeError.busy }
        isVerifyingPasscode = true
        defer { isVerifyingPasscode = false }

        // A lock that has already landed has already won. Half a second of key
        // derivation whose result may not be adopted buys nothing, and the
        // attempt is deliberately not counted — the passcode may well have been
        // right, and it was never tested.
        guard session.currentGeneration == generation else {
            throw PasscodeError.cancelledByLock
        }

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
    ///
    /// A background `lock()` wins over it, on both sides of the verification.
    /// The generation is read before the first `await` and carried through, so
    /// the verification cannot adopt over a lock that landed while this was
    /// getting under way, and the rewrapped key is not stored if one landed
    /// during the derivation. Nothing durable has moved at that point, so
    /// stopping costs the user a retry and keeps the lock they asked for.
    func changePasscode(current: String, new: String, now: Date = Date()) async throws {
        // First statement, ahead of the lease, exactly as `setPasscode` reads
        // it. `lock()` is `nonisolated` and stays outside the coordinator on
        // purpose, so it can land from here on — and a generation read inside
        // the verification below would be read *after* such a lock, letting the
        // adopt undo it.
        let generation = session.currentGeneration

        let lease = try beginTransition()
        defer { coordinator.end(lease) }

        try validate(new)

        let dataKey = try await unlock(with: current, now: now, anchoredTo: generation)
        let rewrapped = try await keyStore.wrap(dataKey, passcode: new)

        // The last instant before the one durable change this method makes. A
        // lock landing during the rewrap loses nothing — the key never left
        // memory and every share is untouched — so the honest outcome is to
        // leave the passcode exactly as the user locked it behind.
        guard session.currentGeneration == generation else {
            throw PasscodeError.cancelledByLock
        }

        try keyStore.storeWrappedDataKey(rewrapped)

        rebindTheBiometricCopy(to: rewrapped, dataKey: dataKey)
    }

    /// The biometric copy is bound to the exact wrapped blob it was made for,
    /// and a change replaces that blob — so without this the shortcut would stop
    /// working the moment anyone changed their passcode.
    ///
    /// Rebinding costs no prompt: writing the item never asks for a face, only
    /// reading does, and the data key has just been verified. If it cannot be
    /// rebound the copy is removed instead — a stale binding is refused at the
    /// next unlock anyway, and leaving one advertises a shortcut the app will
    /// not honour. A failure to remove it is logged rather than thrown: the
    /// passcode change itself succeeded, and the leftover cannot open anything.
    private func rebindTheBiometricCopy(to wrapped: Data, dataKey: SymmetricKey) {
        guard biometrics.isEnabled else { return }

        do {
            try biometrics.enable(dataKey: dataKey, boundTo: wrapped)
        } catch {
            logger.error("Could not rebind the biometric copy after a passcode change; removing it: \(String(describing: error), privacy: .public)")
            do {
                try biometrics.disable()
            } catch {
                logger.error("The superseded biometric copy could not be removed either; it will be refused and cleared at the next unlock: \(String(describing: error), privacy: .public)")
            }
        }
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
    /// A background `lock()` wins, but only up to a point, and the point is
    /// marked in the body. Until the unseal begins, nothing durable has moved
    /// and honouring the lock costs a retry. From the unseal onwards there is no
    /// way back — putting the shares behind the passcode again needs the data
    /// key in the session, and the lock is what removed it — so the call runs to
    /// completion rather than stranding plaintext key material behind a passcode
    /// that is still demanded.
    ///
    /// **Postcondition, and it is the one that keeps a user out of a lock screen
    /// they cannot open.** When this returns without throwing, the passcode is
    /// gone and ``isPasscodeGateRequired`` is therefore `false`. A gate raised
    /// before the mode moved is stale from that instant, and stale is not
    /// harmless here: its only exit is an unlock, and there is nothing left for
    /// an unlock to verify against.
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
        // First statement, ahead of the lease, exactly as `setPasscode` reads it
        // — and here it is load-bearing twice over. It anchors the verification
        // below, so a `lock()` landing while this was getting under way cannot
        // be adopted over; and it is what the abort decision further down is
        // made against.
        let generation = session.currentGeneration

        let lease = try beginTransition()
        defer { coordinator.end(lease) }

        // Read on **both** sides of the verification, and kept for the rollback
        // below. `unlock` cannot succeed without reading this same item, so a
        // read that comes back unreadable on one side of it is transient rather
        // than meaningful — and without these bytes the rollback has nothing to
        // restore, which is the difference between "the passcode is back" and
        // "plaintext shares behind a mode that says there is no passcode".
        let wrappedBeforeVerification = keyStore.loadWrappedDataKey().valueTreatingUnavailableAsAbsent

        let dataKey = try await unlock(with: current, now: now, anchoredTo: generation)

        // The biometric copy goes first, before a single share moves. It holds
        // the same data key, so a survivor would quietly work again the next
        // time a passcode is set, and failing to remove it after the shares had
        // already been opened would report an error over a passcode that was
        // half gone. Nothing has changed yet at this point, so aborting is clean.
        //
        // Called directly rather than through `disableBiometricUnlock()`: this
        // already holds the transition lease, and that one takes a write lease
        // the transition excludes.
        //
        // Whether there was one is captured before it is taken away: restoring
        // on an abort has to put back exactly what was there and nothing else,
        // and re-adding unconditionally would hand the user a shortcut they
        // never enabled.
        let hadBiometricCopy = biometrics.isEnabled
        try biometrics.disable()

        let wrapped = wrappedBeforeVerification
            ?? keyStore.loadWrappedDataKey().valueTreatingUnavailableAsAbsent

        // **The abort cut-off, and it is a one-way door.** Everything above this
        // line is reversible by doing nothing: no share has moved, the wrapper
        // is untouched and the gate is still up, so a lock that landed while the
        // passcode was being verified is honoured simply by stopping. Past this
        // line it is not. The unseal writes plaintext key material to disk, and
        // the only thing that could put it back is a reseal — which needs the
        // data key *in the session*, which is precisely what a lock has just
        // taken away. Aborting there would leave every share in the clear behind
        // a passcode that is still set and still demanded, which is worse than
        // finishing: finishing at least ends somewhere consistent.
        //
        // So: stop here, or see it through. There is no third option.
        guard session.currentGeneration == generation else {
            // "Reversible by doing nothing" is true of everything above this
            // line *except* the biometric copy, which has already been removed
            // on the assumption this would go through. Stopping without putting
            // it back turns the shortcut off silently: the passcode is still
            // set, the disable reports a cancellation, and Face ID is simply
            // gone with nothing said about it.
            restoreBiometricCopyAfterAbort(dataKey, boundTo: wrapped, existed: hadBiometricCopy)
            throw PasscodeError.cancelledByLock
        }

        // And the same line is where the rollback material has to exist. The
        // verification cannot have succeeded without reading this item as
        // `.present`, so both reads around it coming back empty means the
        // Keychain went quiet either side of one that answered — not that the
        // wrapper is gone. Crossing without those bytes would leave a failed
        // removal with nothing to put back, and the reseal it needs is on the
        // wrong side of the door. Nothing has moved yet, so refuse.
        guard let wrapped else {
            // Same door, same debt — and here it cannot be paid: the binding a
            // restored copy needs is the wrapper these very bytes are missing.
            restoreBiometricCopyAfterAbort(dataKey, boundTo: nil, existed: hadBiometricCopy)
            throw PasscodeError.storageFailure
        }

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
    ///
    /// The bytes are non-optional because the removal never begins without
    /// them: a disable that cannot see the wrapper on either side of its own
    /// verification refuses before it opens a single share.
    private func restorePasscodeAfterFailedRemoval(wrapped: Data) async throws {
        do {
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

    /// Drops the persisted passcode mode once the passcode is confirmed gone.
    ///
    /// The same rule ``KeyshareInstallReconciler`` applies at launch, applied at
    /// the one other moment it matters: a `.passcode` mode with no wrapper
    /// behind it is a door with nothing to open it, and whoever is looking at
    /// that door needs ``isPasscodeGateRequired`` to start answering `false`
    /// before they will take it away.
    private func lowerThePasscodeGateWithNothingBehindIt() {
        guard lockService.mode == .passcode else { return }
        logger.warning("A passcode gate outlived its wrapped key; falling back to device auth")
        lockService.mode = .deviceAuth
    }

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

    /// The same claim, for the two operations that move the biometric copy.
    /// They are not transitions — no share is touched and no wrapper is written
    /// — but they must not interleave with one, because a set and a disable both
    /// decide what the copy should be.
    private func beginBiometricWrite() throws -> WriteLease {
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

    /// Six ASCII digits, and `isASCII` is doing real work there.
    ///
    /// `Character.isNumber` is true of every Unicode numeric character — Arabic-
    /// Indic and Devanagari digits, but also `½` and `Ⅷ`. The iOS keypad can
    /// only emit `0`–`9`, so nothing typed there was ever affected; the macOS
    /// field takes a hardware keyboard and a paste, so a passcode of six such
    /// characters could be set on the Mac and then be literally unenterable on
    /// the phone. It also quietly widened the space the attempt limiter's
    /// arithmetic is written against.
    private func validate(_ passcode: String) throws {
        guard passcode.count == Self.passcodeLength,
              passcode.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw PasscodeError.invalidLength
        }
    }
}
