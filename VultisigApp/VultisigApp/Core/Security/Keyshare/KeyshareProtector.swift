//
//  KeyshareProtector.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import OSLog

private let logger = Log.app.store

enum KeyshareProtectionError: Error, Equatable {
    /// A share is sealed but the data key is not available to open it.
    case locked
    case cipherFailure
}

/// Whether key shares are protected, and if so whether the key is available.
enum KeyshareProtectionState {
    /// No data key exists — shares are stored in the clear. The state every
    /// install is in until the one-time migration runs.
    case disabled
    /// The data key is in hand; shares seal and open.
    case unlocked(SymmetricKey)
    /// A data key exists but is wrapped by a passcode that has not been entered.
    case locked
}

/// The single point where a stored key share turns into a usable one.
///
/// Every read and write of `KeyShare.keyshare` goes through here, so the choice
/// of whether a share is encrypted lives in exactly one place instead of being
/// spread across keygen, keysign, reshare and backup.
///
/// `open` tolerates a plaintext value whatever the state, because shares stay
/// plaintext until the migration has run and the migration must be safe to
/// retry. `seal` refuses to double-seal for the same reason.
protocol KeyshareProtecting {
    func open(_ stored: String) throws -> String
    func seal(_ plaintext: String) throws -> String
    /// Whether a stored value is ciphertext rather than a plaintext share.
    func isSealed(_ stored: String) -> Bool
}

final class KeyshareProtector: KeyshareProtecting {

    static let shared = KeyshareProtector()

    private let cipher: KeyshareCipher
    private let state: () -> KeyshareProtectionState

    init(
        cipher: KeyshareCipher = AesGcmKeyshareCipher(),
        state: @escaping () -> KeyshareProtectionState = { KeyshareKeySession.shared.currentState() }
    ) {
        self.cipher = cipher
        self.state = state
    }

    func isSealed(_ stored: String) -> Bool {
        cipher.isSealed(stored)
    }

    func open(_ stored: String) throws -> String {
        // A share written before the migration is plaintext and stays readable
        // regardless of state — that is what makes the migration resumable.
        guard cipher.isSealed(stored) else { return stored }

        switch state() {
        case .unlocked(let key):
            do {
                return try cipher.open(stored, with: key)
            } catch {
                logger.error("Failed to open key share: \(String(describing: error), privacy: .public)")
                throw KeyshareProtectionError.cipherFailure
            }
        case .disabled, .locked:
            // Sealed with no key in hand. Never fall back to returning the
            // ciphertext: a caller handing that to the TSS layer would look like
            // a corrupt share rather than a locked app.
            throw KeyshareProtectionError.locked
        }
    }

    func seal(_ plaintext: String) throws -> String {
        guard !cipher.isSealed(plaintext) else { return plaintext }

        switch state() {
        case .unlocked(let key):
            do {
                return try cipher.seal(plaintext, with: key)
            } catch {
                logger.error("Failed to seal key share: \(String(describing: error), privacy: .public)")
                throw KeyshareProtectionError.cipherFailure
            }
        case .disabled:
            return plaintext
        case .locked:
            throw KeyshareProtectionError.locked
        }
    }
}
