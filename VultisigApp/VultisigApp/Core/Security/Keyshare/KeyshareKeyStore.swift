//
//  KeyshareKeyStore.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import OSLog
import Security

private let logger = Log.app.other

enum KeyshareKeyStoreError: Error, Equatable {
    /// The Keychain accepted the write but read back something else — treated
    /// as a hard failure, because encrypting against a key we cannot prove is
    /// durable is how key shares get lost.
    case persistenceFailed
    case wrongPasscode
    case malformedWrappedKey
    /// The Keychain reported success but the item is still readable.
    case deletionFailed
}

/// Custody of the data key that encrypts key shares at rest.
///
/// The data key is 256 random bits, never derived from anything the user types.
/// A key share is sealed if and only if a passcode is set, so:
///
/// - **no passcode** — no key of either form exists and every stored share is
///   plaintext, byte-for-byte what a build without this feature would write.
/// - **passcode set** — the key is persisted only in passcode-wrapped form.
///   Unlocking opens it; locking forgets the opened key.
///
/// Because a share is sealed under the data key rather than under the passcode,
/// changing the passcode rewraps 32 bytes and never rewrites a single key share.
///
/// The unwrapped-key API (`loadDataKey` / `storeDataKey` / `deleteDataKey`) is
/// what remains of an earlier design that kept a clear copy alongside the
/// shares. **Nothing writes one any more** — the disable path opens every share
/// instead of stashing the key — so what is left is a read path that recognises
/// an item inherited from such a build, and it goes with the item itself.
///
/// **Every read answers with a ``KeychainReadResult``, and the distinction is
/// load-bearing rather than decorative.** `.absent` is the only answer that
/// licenses minting a fresh data key, and a fresh key cannot open a single
/// share the old one sealed — so an unreadable Keychain reported as absence is
/// a direct path to permanently orphaned key material. Deletions verify against
/// a *confirmed* absence for the same reason.
protocol KeyshareKeyStoring {
    func generateDataKey() throws -> SymmetricKey

    func loadDataKey() -> KeychainReadResult<SymmetricKey>
    func storeDataKey(_ key: SymmetricKey) throws
    func deleteDataKey() throws

    func loadWrappedDataKey() -> KeychainReadResult<Data>
    func storeWrappedDataKey(_ blob: Data) throws
    func deleteWrappedDataKey() throws

    func wrap(_ key: SymmetricKey, passcode: String) async throws -> Data
    func unwrap(_ blob: Data, passcode: String) async throws -> SymmetricKey
}

final class DefaultKeyshareKeyStore: KeyshareKeyStoring {

    static let shared: KeyshareKeyStoring = DefaultKeyshareKeyStore()

    private let keychain: KeychainService

    init(keychain: KeychainService = DefaultKeychainService.shared) {
        self.keychain = keychain
    }

    // MARK: - Data key

    func generateDataKey() throws -> SymmetricKey {
        try VaultCryptoEnvelope.randomKey()
    }

    /// - Returns: ``KeychainReadResult/unavailable(_:)`` with `errSecDecode` when
    ///   an item exists but is not a 256-bit key. It is present and unusable,
    ///   which is not the same as absent: reporting absence would let a caller
    ///   write a replacement over key material that is still there.
    func loadDataKey() -> KeychainReadResult<SymmetricKey> {
        switch keychain.getKeyshareDataKey() {
        case .absent:
            return .absent
        case .unavailable(let status):
            return .unavailable(status)
        case .present(let data):
            guard data.count == VaultCryptoEnvelope.keyLengthBytes else {
                logger.error("Keyshare data key has unexpected length \(data.count, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .present(SymmetricKey(data: data))
        }
    }

    /// Writes the key and reads it back before returning. A silent Keychain
    /// failure here would otherwise surface later as unopenable key shares.
    func storeDataKey(_ key: SymmetricKey) throws {
        let data = key.rawRepresentation
        keychain.setKeyshareDataKey(data)

        guard case .present(let readBack) = keychain.getKeyshareDataKey(), readBack == data else {
            logger.error("Keyshare data key failed read-back verification")
            throw KeyshareKeyStoreError.persistenceFailed
        }
    }

    /// Verifies the item is actually gone.
    ///
    /// A silent deletion failure here is what makes a passcode cosmetic: the
    /// clear copy would survive, and the next lock would simply reload it from
    /// the Keychain and carry on signing.
    ///
    /// Only a **confirmed** absence counts. An unreadable item may still be
    /// there, and callers record a successful clear as done and never retry it.
    func deleteDataKey() throws {
        keychain.setKeyshareDataKey(nil)

        guard case .absent = keychain.getKeyshareDataKey() else {
            logger.error("Keyshare data key still present or unreadable after deletion")
            throw KeyshareKeyStoreError.deletionFailed
        }
    }

    // MARK: - Wrapped data key

    func loadWrappedDataKey() -> KeychainReadResult<Data> {
        keychain.getWrappedKeyshareDataKey()
    }

    func storeWrappedDataKey(_ blob: Data) throws {
        keychain.setWrappedKeyshareDataKey(blob)

        guard case .present(let readBack) = keychain.getWrappedKeyshareDataKey(), readBack == blob else {
            logger.error("Wrapped keyshare data key failed read-back verification")
            throw KeyshareKeyStoreError.persistenceFailed
        }
    }

    /// Verified against a confirmed absence, for the same reason
    /// ``deleteDataKey()`` is.
    func deleteWrappedDataKey() throws {
        keychain.setWrappedKeyshareDataKey(nil)

        guard case .absent = keychain.getWrappedKeyshareDataKey() else {
            logger.error("Wrapped keyshare data key still present or unreadable after deletion")
            throw KeyshareKeyStoreError.deletionFailed
        }
    }

    // MARK: - Passcode wrapping

    /// PBKDF2 at 600k iterations costs roughly half a second, so both of these
    /// run off the calling thread the way `VaultBackupEncryption` does.
    ///
    /// The stretching is not what makes the wrap strong — a 5-digit passcode is
    /// only ~16.6 bits however it is stretched, and an attacker who can read the
    /// wrapped blob out of the Keychain already owns the device. What it buys is
    /// a throttle on the in-app guessing path.
    func wrap(_ key: SymmetricKey, passcode: String) async throws -> Data {
        let keyData = key.rawRepresentation
        return try await Task.detached(priority: .userInitiated) {
            let salt = try VaultCryptoEnvelope.randomBytes(count: VaultCryptoEnvelope.saltLength)
            let iv = try VaultCryptoEnvelope.randomBytes(count: VaultCryptoEnvelope.ivLength)
            let wrappingKey = try VaultCryptoEnvelope.deriveKey(password: passcode, salt: salt)
            return try VaultCryptoEnvelope.seal(keyData, using: wrappingKey, salt: salt, iv: iv)
        }.value
    }

    /// A wrong passcode fails GCM authentication, which is what makes a separate
    /// stored verification sample unnecessary.
    func unwrap(_ blob: Data, passcode: String) async throws -> SymmetricKey {
        try await Task.detached(priority: .userInitiated) {
            guard let parsed = VaultCryptoEnvelope.parse(blob) else {
                throw KeyshareKeyStoreError.malformedWrappedKey
            }

            let wrappingKey = try VaultCryptoEnvelope.deriveKey(password: passcode, salt: parsed.salt)

            let keyData: Data
            do {
                keyData = try VaultCryptoEnvelope.open(parsed, using: wrappingKey)
            } catch {
                throw KeyshareKeyStoreError.wrongPasscode
            }

            guard keyData.count == VaultCryptoEnvelope.keyLengthBytes else {
                throw KeyshareKeyStoreError.malformedWrappedKey
            }
            return SymmetricKey(data: keyData)
        }.value
    }
}

private extension SymmetricKey {
    var rawRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}
