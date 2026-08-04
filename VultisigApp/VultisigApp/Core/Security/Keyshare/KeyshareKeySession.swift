//
//  KeyshareKeySession.swift
//  VultisigApp
//

import CryptoKit
import Foundation

/// Holds the data key for the life of an unlocked session.
///
/// The key never comes out of the Keychain *here*: an unlock hands the opened
/// key over through `adopt`, and it is then held in memory, because the read
/// path runs inside TSS keygen and keysign — `getLocalState` is called per share
/// by the signing layer, and paying a Keychain round trip each time would put
/// that cost in the middle of signing. Forgetting it is therefore all `clear()`
/// has to do to lock the app.
///
/// A data key exists only while a passcode does. With none set the store holds
/// no key, the session reports `.disabled`, and stored shares stay plaintext —
/// the state the great majority of installs are in and stay in.
///
/// There is no unwrapped form of the key anywhere: the Keychain holds it only
/// passcode-wrapped, and removing the passcode opens every share rather than
/// stashing the key beside them.
///
/// The presence of the **wrapped** key is therefore the whole of the persisted
/// state, and reading it is the one place a Keychain failure could do real harm:
/// answering `.disabled` when the key is merely unreadable would tell every
/// caller that shares are plaintext, and the next `seal` would write one in the
/// clear behind a passcode that is still set. So an unreadable Keychain reads as
/// `.locked` — the app refuses to touch key material until it can see its own
/// state again.
final class KeyshareKeySession {

    static let shared = KeyshareKeySession()

    private let store: KeyshareKeyStoring
    private let lock = NSLock()
    private var cachedKey: SymmetricKey?
    /// Bumped on every `clear()`. An unlock that began before a lock happened
    /// must not install its result afterwards.
    private var generation: Int = 0

    init(store: KeyshareKeyStoring = DefaultKeyshareKeyStore.shared) {
        self.store = store
    }

    /// - `unlocked` — the key is in hand.
    /// - `locked` — a wrapped key exists but has not been opened, **or** the
    ///   Keychain could not be read and so may hold one.
    /// - `disabled` — the Keychain positively answered that there is no wrapped
    ///   key: no passcode, and shares are plaintext.
    func currentState() -> KeyshareProtectionState {
        lock.lock()
        defer { lock.unlock() }

        if let cachedKey {
            return .unlocked(cachedKey)
        }
        switch store.loadWrappedDataKey() {
        case .present:
            return .locked
        case .absent:
            return .disabled
        case .unavailable:
            // Fail closed, and the cost is understood: `seal` throws on
            // `.locked`, so a Keychain that cannot be read fails a keygen or an
            // import rather than completing it. That is the better half of the
            // trade. `.disabled` is a licence to write plaintext, and taking it
            // wrongly writes an unprotected share behind a passcode that is
            // still set — silently, and only for the users who opted in.
            // Failing is visible and the user retries.
            //
            // The exposure is also narrower than it looks: with no passcode
            // there is no wrapped item, and a query matching no item answers
            // `errSecItemNotFound` whatever the device's lock state. Reaching
            // this line without a passcode takes a Keychain-wide fault, which
            // the fast-vault password and device-token reads would be failing
            // on too.
            return .locked
        }
    }

    /// Adopts a key without going back to the Keychain — used when a key has
    /// just been generated or unwrapped and is already in hand.
    func adopt(_ key: SymmetricKey) {
        lock.lock()
        defer { lock.unlock() }
        cachedKey = key
    }

    /// The generation to pass back to `adopt(_:ifGeneration:)`.
    var currentGeneration: Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// Adopts the key only if no `clear()` happened in the meantime.
    ///
    /// Unlocking runs PBKDF2, which takes long enough for the app to be
    /// backgrounded and locked mid-derivation. Without this check the unlock
    /// would finish afterwards and quietly undo the lock.
    ///
    /// - Returns: whether the key was adopted.
    @discardableResult
    func adopt(_ key: SymmetricKey, ifGeneration expected: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard generation == expected else { return false }
        cachedKey = key
        return true
    }

    /// Forgets the key. Sealed shares become unreadable until it is restored.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cachedKey = nil
        generation &+= 1
    }
}
