//
//  KeyshareKeySession.swift
//  VultisigApp
//

import CryptoKit
import Foundation

/// Holds the data key for the life of an unlocked session.
///
/// The key is read from the Keychain once and kept in memory afterwards, because
/// the read path runs inside TSS keygen and keysign — `getLocalState` is called
/// per share by the signing layer, and paying a Keychain round trip each time
/// would put that cost in the middle of signing.
///
/// While no passcode exists the key sits in the Keychain in the clear, so the
/// session can always repopulate itself. Once a passcode is set the clear copy
/// is gone and only an unlock can fill this in, which is what makes `clear()`
/// equivalent to locking.
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

    /// - `disabled` — no data key of either form: shares are still plaintext.
    /// - `unlocked` — the key is in hand.
    /// - `locked` — a wrapped key exists but has not been opened.
    func currentState() -> KeyshareProtectionState {
        lock.lock()
        defer { lock.unlock() }

        if let cachedKey {
            return .unlocked(cachedKey)
        }
        if let key = store.loadDataKey() {
            cachedKey = key
            return .unlocked(key)
        }
        if store.loadWrappedDataKey() != nil {
            return .locked
        }
        return .disabled
    }

    /// Adopts a key without going back to the Keychain — used by the migration,
    /// which has just generated and persisted one, and later by unlock.
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
