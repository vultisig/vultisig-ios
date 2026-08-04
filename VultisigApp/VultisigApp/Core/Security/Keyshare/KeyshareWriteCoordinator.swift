//
//  KeyshareWriteCoordinator.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Log.app.store

enum KeyshareWriteCoordinatorError: Error, Equatable {
    /// Another passcode transition, key-share write, or vault-creation episode
    /// holds the coordinator.
    case busy
}

/// Serializes passcode transitions against every path that writes a key share.
///
/// A key share is sealed if and only if a passcode is set, so the moment a
/// passcode is added or removed every stored share has to move with it. Two
/// things can race that:
///
/// 1. two transitions, because the service that performs them suspends across
///    key derivation and actors are reentrant at every `await`;
/// 2. a key-share write, which computes its ciphertext under one protection
///    state and persists it later — possibly under another. Sealing during a
///    disable and appending after the wrapped key is gone leaves a share nothing
///    can ever open.
///
/// **Not `@MainActor`, and deliberately lock-based rather than an actor.** The
/// hottest caller is `LocalStateAccessorImpl.saveLocalState`, a *synchronous*
/// callback the TSS layer makes from an arbitrary thread. An actor or a
/// main-actor hop would force the body into a `Task`, and the seal would then
/// land outside the span that is supposed to make it indivisible;
/// `DispatchQueue.main.sync` would deadlock whenever the callback already runs on
/// main. So this is the same shape `KeyshareKeySession` already uses on this exact
/// call path: an `NSLock` and no suspension points.
///
/// Three lease levels, because the three hazards have three different lifetimes:
///
/// | Lease | Span | Prevents |
/// |---|---|---|
/// | `TransitionLease` | one set / change / disable / resume, taken before the first `await` | two transitions interleaving across key derivation |
/// | write lease | one seal **and** its persistence, synchronously | a value sealed under one state being stored under another |
/// | `EpisodeLease` | a whole keygen / reshare / import, start through commit or discard | a share produced before a transition and committed after it |
///
/// A transition is exclusive against all three; writes and episodes are not
/// exclusive against each other, so ordinary vault creation is never serialized
/// against itself. Contention is reported as `.busy` rather than queued: an
/// honest "finish creating your vault first" beats a lock-free protocol nobody
/// can review.
final class KeyshareWriteCoordinator {

    static let shared = KeyshareWriteCoordinator()

    private let lock = NSLock()
    private var isTransitionHeld = false
    private var writesInFlight = 0
    private var openEpisodes = 0

    // MARK: - Transitions

    /// Claims exclusive access for one passcode set / change / disable / resume.
    ///
    /// Must be taken **before the first `await`** in the operation it protects,
    /// or two callers can both get past their own preconditions and interleave.
    ///
    /// - Throws: `KeyshareWriteCoordinatorError.busy` if another transition is
    ///   held, a key-share write is in flight, or a vault-creation episode is
    ///   open.
    func beginTransition() throws -> TransitionLease {
        lock.lock()

        guard !isTransitionHeld, writesInFlight == 0, openEpisodes == 0 else {
            let held = describeHoldersLocked()
            lock.unlock()
            logger.info("Passcode transition refused; \(held, privacy: .public)")
            throw KeyshareWriteCoordinatorError.busy
        }

        isTransitionHeld = true
        lock.unlock()

        // The lease holds the coordinator, not the other way round, so a lease
        // that outlives every other reference still releases against the
        // instance it was taken from.
        return TransitionLease { self.releaseTransition() }
    }

    /// Releases a transition lease. Calling it twice, or after the lease has
    /// already been dropped, is a no-op.
    func end(_ lease: TransitionLease) {
        lease.release()
    }

    // MARK: - Single writes

    /// Runs `body` as one indivisible key-share write — the seal and the store
    /// that follows it cannot be split by a transition.
    ///
    /// Synchronous by construction: `body` runs on the calling thread with no
    /// suspension point, because the TSS callback this exists for cannot await.
    ///
    /// - Throws: `KeyshareWriteCoordinatorError.busy` if a transition holds the
    ///   coordinator, or whatever `body` throws.
    func withWriteLease<T>(_ body: () throws -> T) throws -> T {
        try claimWrite()
        defer { releaseWrite() }
        return try body()
    }

    /// The same claim as ``withWriteLease(_:)``, held as a token, for the one
    /// caller that has to `await` in the middle of it: the app unlock, which
    /// unwraps the data key and then finishes any sweep an interrupted
    /// transition left behind.
    ///
    /// **A write and not a transition, deliberately.** A transition is refused
    /// while a vault-creation episode is open, and keygen holds one from the
    /// protocol starting through the deferred commit — so an app that locked on
    /// the review screen could never be opened again: the flow cannot be
    /// finished without unlocking, and unlocking cannot happen while the flow is
    /// open. Excluding transitions is all an unlock needs, and that is exactly
    /// what a write lease does.
    ///
    /// - Throws: `KeyshareWriteCoordinatorError.busy` if a transition is held.
    func beginWrite() throws -> WriteLease {
        try claimWrite()
        return WriteLease { self.releaseWrite() }
    }

    /// Releases a write lease. Calling it twice, or after the lease has already
    /// been dropped, is a no-op.
    func end(_ lease: WriteLease) {
        lease.release()
    }

    // MARK: - Episodes

    /// Claims a vault-creation episode: keygen, reshare or import, from the
    /// moment the protocol starts through the commit that persists its shares,
    /// or through the discard that throws them away.
    ///
    /// This is the window a per-write lease cannot cover. TSS hands over a share
    /// long before `commitVault` stores it, and a passcode set landing in between
    /// would sweep the store without ever seeing that share — which would then be
    /// inserted in plaintext behind a passcode.
    ///
    /// - Returns: `nil` if a transition holds the coordinator. Episodes do not
    ///   exclude each other.
    func beginEpisode() -> EpisodeLease? {
        lock.lock()
        guard !isTransitionHeld else {
            lock.unlock()
            logger.info("Vault-creation episode refused; a passcode transition is in progress")
            return nil
        }
        openEpisodes += 1
        lock.unlock()

        return EpisodeLease { self.releaseEpisode() }
    }

    /// Releases an episode lease. Calling it twice, or after the lease has
    /// already been dropped, is a no-op.
    func end(_ lease: EpisodeLease) {
        lease.release()
    }

    // MARK: - Privates

    private func claimWrite() throws {
        lock.lock()
        guard !isTransitionHeld else {
            lock.unlock()
            logger.info("Key-share write refused; a passcode transition is in progress")
            throw KeyshareWriteCoordinatorError.busy
        }
        writesInFlight += 1
        lock.unlock()
    }

    private func releaseWrite() {
        lock.lock()
        writesInFlight -= 1
        lock.unlock()
    }

    private func releaseTransition() {
        lock.lock()
        isTransitionHeld = false
        lock.unlock()
    }

    private func releaseEpisode() {
        lock.lock()
        openEpisodes -= 1
        lock.unlock()
    }

    /// Caller must hold `lock`.
    private func describeHoldersLocked() -> String {
        var holders: [String] = []
        if isTransitionHeld { holders.append("another transition") }
        if writesInFlight > 0 { holders.append("\(writesInFlight) key-share write(s)") }
        if openEpisodes > 0 { holders.append("\(openEpisodes) open episode(s)") }
        return "held by " + holders.joined(separator: ", ")
    }
}

// MARK: - Leases

/// A lease that releases exactly once, whether it is ended explicitly or simply
/// dropped.
///
/// `deinit` releasing is the point: an episode brackets a flow with a great many
/// error and cancellation paths, and a leaked lease would block every passcode
/// change until the app is relaunched. Holding the token in a `defer`, or in a
/// property that goes away with the flow, is therefore enough.
class KeyshareLease {

    private let releaseAction: () -> Void
    private let lock = NSLock()
    private var isReleased = false

    fileprivate init(_ release: @escaping () -> Void) {
        self.releaseAction = release
    }

    fileprivate func release() {
        lock.lock()
        let wasReleased = isReleased
        isReleased = true
        lock.unlock()

        guard !wasReleased else { return }
        releaseAction()
    }

    deinit {
        release()
    }
}

/// Held for the duration of one passcode set, change, disable or resume.
final class TransitionLease: KeyshareLease {}

/// Held for the duration of one key-share write that has to `await`.
final class WriteLease: KeyshareLease {}

/// Held for the duration of one keygen, reshare or vault import.
final class EpisodeLease: KeyshareLease {}
