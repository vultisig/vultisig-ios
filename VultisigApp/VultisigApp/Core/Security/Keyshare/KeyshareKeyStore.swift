//
//  KeyshareKeyStore.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import OSLog

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
/// shares. Nothing writes one any more.
protocol KeyshareKeyStoring {
    func generateDataKey() throws -> SymmetricKey

    func loadDataKey() -> SymmetricKey?
    func storeDataKey(_ key: SymmetricKey) throws
    func deleteDataKey() throws

    func loadWrappedDataKey() -> Data?
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

    func loadDataKey() -> SymmetricKey? {
        guard let data = keychain.getKeyshareDataKey().valueTreatingUnavailableAsAbsent else { return nil }
        guard data.count == VaultCryptoEnvelope.keyLengthBytes else {
            logger.error("Keyshare data key has unexpected length \(data.count, privacy: .public)")
            return nil
        }
        return SymmetricKey(data: data)
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
    func deleteDataKey() throws {
        keychain.setKeyshareDataKey(nil)

        guard keychain.getKeyshareDataKey().valueTreatingUnavailableAsAbsent == nil else {
            logger.error("Keyshare data key still present after deletion")
            throw KeyshareKeyStoreError.deletionFailed
        }
    }

    // MARK: - Wrapped data key

    func loadWrappedDataKey() -> Data? {
        keychain.getWrappedKeyshareDataKey().valueTreatingUnavailableAsAbsent
    }

    func storeWrappedDataKey(_ blob: Data) throws {
        keychain.setWrappedKeyshareDataKey(blob)

        guard case .present(let readBack) = keychain.getWrappedKeyshareDataKey(), readBack == blob else {
            logger.error("Wrapped keyshare data key failed read-back verification")
            throw KeyshareKeyStoreError.persistenceFailed
        }
    }

    func deleteWrappedDataKey() throws {
        keychain.setWrappedKeyshareDataKey(nil)

        guard keychain.getWrappedKeyshareDataKey().valueTreatingUnavailableAsAbsent == nil else {
            logger.error("Wrapped keyshare data key still present after deletion")
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
