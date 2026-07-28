import CryptoKit
import Foundation
import OSLog

private let logger = Log.app.other

protocol VaultBackupEncryption: Sendable {
    func encrypt(data: Data, password: String) async throws -> Data
    func decrypt(data: Data, password: String) async -> Data?
}

enum VaultBackupEncryptionError: Error {
    case keyDerivationFailed
    case randomGenerationFailed
    case encryptionFailed
}

/// Vault backups, encrypted under a user-chosen password.
///
/// The blob format lives in `VaultCryptoEnvelope`, which key shares at rest
/// share — the bytes on the wire are unchanged, and stay compatible with the
/// desktop client's backups.
final class Pbkdf2VaultBackupEncryption: VaultBackupEncryption {

    func encrypt(data: Data, password: String) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Self.encryptSync(data: data, password: password)
        }.value
    }

    func decrypt(data: Data, password: String) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            Self.decryptSync(data: data, password: password)
        }.value
    }

    private static func encryptSync(data: Data, password: String) throws -> Data {
        do {
            let salt = try VaultCryptoEnvelope.randomBytes(count: VaultCryptoEnvelope.saltLength)
            let iv = try VaultCryptoEnvelope.randomBytes(count: VaultCryptoEnvelope.ivLength)
            let key = try VaultCryptoEnvelope.deriveKey(password: password, salt: salt)
            return try VaultCryptoEnvelope.seal(data, using: key, salt: salt, iv: iv)
        } catch let error as VaultCryptoEnvelopeError {
            throw error.asBackupError
        }
    }

    private static func decryptSync(data: Data, password: String) -> Data? {
        if let plaintext = decryptPbkdf2(data: data, password: password) {
            return plaintext
        }
        // Legacy blobs begin with a random nonce that may, with ~1/2^32 probability,
        // collide with the format signature. Fall back so those backups stay importable.
        return legacyDecrypt(data: data, password: password)
    }

    private static func decryptPbkdf2(data: Data, password: String) -> Data? {
        guard let parsed = VaultCryptoEnvelope.parse(data) else {
            return nil
        }

        do {
            let key = try VaultCryptoEnvelope.deriveKey(password: password, salt: parsed.salt)
            return try VaultCryptoEnvelope.open(parsed, using: key)
        } catch {
            logger.error("PBKDF2 decryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func legacyDecrypt(data: Data, password: String) -> Data? {
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            logger.error("Legacy decryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

private extension VaultCryptoEnvelopeError {
    /// Preserves the errors this type has always thrown, so callers switching on
    /// `VaultBackupEncryptionError` are unaffected by the move to the shared
    /// envelope.
    var asBackupError: VaultBackupEncryptionError {
        switch self {
        case .keyDerivationFailed:
            return .keyDerivationFailed
        case .randomGenerationFailed:
            return .randomGenerationFailed
        case .encryptionFailed, .malformedBlob, .decryptionFailed:
            return .encryptionFailed
        }
    }
}
