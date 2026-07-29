//
//  PasscodeService.swift
//  VultisigApp
//

import CryptoKit
import Foundation

enum PasscodeError: Error, Equatable {
    case wrongPasscode
    case notSet
    case alreadySet
    /// No data key to wrap — the migration has not run, so there is nothing to
    /// protect yet.
    case noDataKey
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
actor PasscodeService {

    static let shared = PasscodeService()

    static let passcodeLength = 5

    private let keyStore: KeyshareKeyStoring
    private let session: KeyshareKeySession
    private let lockService: AppLockService
    private let limiter: PasscodeAttemptLimiting

    init(
        keyStore: KeyshareKeyStoring = DefaultKeyshareKeyStore.shared,
        session: KeyshareKeySession = .shared,
        lockService: AppLockService = .shared,
        limiter: PasscodeAttemptLimiting = PasscodeAttemptLimiter()
    ) {
        self.keyStore = keyStore
        self.session = session
        self.lockService = lockService
        self.limiter = limiter
    }

    var isSet: Bool {
        keyStore.loadWrappedDataKey() != nil
    }

    // MARK: - Set

    func setPasscode(_ passcode: String) async throws {
        try validate(passcode)
        guard !isSet else { throw PasscodeError.alreadySet }

        guard let dataKey = keyStore.loadDataKey() else {
            // Nothing is encrypted yet, so there is no key to put behind a
            // passcode. Wrapping a key we just invented would leave the shares
            // readable without it and misrepresent what the passcode protects.
            throw PasscodeError.noDataKey
        }

        let wrapped = try await keyStore.wrap(dataKey, passcode: passcode)
        try keyStore.storeWrappedDataKey(wrapped)

        // Only once the wrapped copy is stored and verified does the clear copy
        // go. The other order loses the key outright if the write fails.
        //
        // Verified, and the mode is only switched afterwards: a silently failed
        // deletion would leave the clear copy readable, so locking would just
        // reload it from the Keychain and the passcode would be decorative.
        do {
            try keyStore.deleteDataKey()
        } catch {
            // Both copies exist. Left alone, `isSet` would report a passcode
            // while the mode stayed on device auth and every retry failed with
            // `alreadySet` — a passcode screen protecting nothing, with no way
            // out. Undo the wrapped copy so the app is back where it started.
            guard (try? keyStore.deleteWrappedDataKey()) != nil else {
                throw PasscodeError.inconsistentState
            }
            throw error
        }

        session.adopt(dataKey)
        lockService.mode = .passcode
        limiter.recordSuccess()
    }

    // MARK: - Unlock

    @discardableResult
    func unlock(with passcode: String, now: Date = Date()) async throws -> SymmetricKey {
        let lockout = limiter.remainingLockout(now: now)
        guard lockout <= 0 else {
            throw PasscodeError.lockedOut(remaining: lockout)
        }

        guard let wrapped = keyStore.loadWrappedDataKey() else {
            throw PasscodeError.notSet
        }

        // Captured before the derivation, which takes long enough for the app to
        // be backgrounded and locked while it runs. Adopting the result
        // afterwards would silently undo that lock.
        let generation = session.currentGeneration

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
    func changePasscode(current: String, new: String, now: Date = Date()) async throws {
        try validate(new)

        let dataKey = try await unlock(with: current, now: now)
        let rewrapped = try await keyStore.wrap(dataKey, passcode: new)
        try keyStore.storeWrappedDataKey(rewrapped)
    }

    // MARK: - Disable

    /// Puts the data key back in the clear and removes the wrapped copy.
    ///
    /// Shares stay sealed on disk — at-rest encryption does not depend on the
    /// passcode, so turning the passcode off does not turn encryption off.
    func disablePasscode(current: String, now: Date = Date()) async throws {
        let dataKey = try await unlock(with: current, now: now)

        // Clear copy first, and it verifies its own read-back: deleting the
        // wrapped copy before the replacement is durable would leave no way to
        // reach the shares at all.
        try keyStore.storeDataKey(dataKey)

        do {
            try keyStore.deleteWrappedDataKey()
        } catch {
            // Both copies now exist, which would leave the app claiming a
            // passcode while the readable clear key makes it meaningless. Undo
            // the clear copy so the passcode keeps protecting something.
            guard (try? keyStore.deleteDataKey()) != nil else {
                // Neither copy can be removed. The clear key is readable, so
                // there is no gate — say so rather than let the app assert one
                // it does not have.
                lockService.mode = .deviceAuth
                throw PasscodeError.inconsistentState
            }
            throw error
        }

        session.adopt(dataKey)
        lockService.mode = .deviceAuth
        limiter.recordSuccess()
    }

    // MARK: - Helpers

    private func validate(_ passcode: String) throws {
        guard passcode.count == Self.passcodeLength,
              passcode.allSatisfy(\.isNumber) else {
            throw PasscodeError.invalidLength
        }
    }
}
