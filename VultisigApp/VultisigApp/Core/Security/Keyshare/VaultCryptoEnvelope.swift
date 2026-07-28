//
//  VaultCryptoEnvelope.swift
//  VultisigApp
//

import CommonCrypto
import CryptoKit
import Foundation
import OSLog

private let logger = Log.app.other

enum VaultCryptoEnvelopeError: Error {
    case keyDerivationFailed
    case randomGenerationFailed
    case encryptionFailed
    case malformedBlob
    case decryptionFailed
}

/// Shared primitives for the `VLT\x02` encrypted blob.
///
/// Wire format is `signature(4) ‖ salt(16) ‖ nonce(12) ‖ ciphertext ‖ tag(16)`,
/// where everything from the nonce onward is CryptoKit's `SealedBox.combined`.
/// It matches the desktop client's vault-backup blob byte for byte, so one
/// implementation serves every at-rest payload we have:
///
/// - vault backups, keyed by a user-chosen password (`VaultBackupEncryption`),
/// - key shares at rest, keyed by a raw random data key,
/// - that data key itself, wrapped under the app passcode.
///
/// The salt is only meaningful for the password-derived payloads; raw-key
/// callers still fill it with random bytes so every blob has the same shape and
/// one parser covers all of them.
///
/// Note that the header is **not** covered by the GCM tag — only the ciphertext
/// is. For password-derived payloads that costs nothing, because a corrupted
/// salt derives a different key and the tag then fails anyway. For raw-key
/// payloads the salt is inert: corrupting it cannot change the plaintext that
/// comes back. Authenticating the header would break every backup already
/// written, so it stays out; nothing reads the salt on the raw-key path, which
/// is what makes that safe.
enum VaultCryptoEnvelope {

    static let formatSignature: [UInt8] = [0x56, 0x4C, 0x54, 0x02]
    static let formatSignatureLength = 4
    static let saltLength = 16
    static let ivLength = 12
    static let gcmTagBytes = 16
    static let keyLengthBytes = 32
    static let pbkdf2Iterations: UInt32 = 600_000

    /// Bytes before the ciphertext: signature + salt + nonce. The nonce is part
    /// of `SealedBox.combined`, so parsing keeps it with the sealed remainder.
    static let headerSize = formatSignatureLength + saltLength + ivLength

    struct Parsed {
        /// PBKDF2 salt. Random filler for raw-key payloads.
        let salt: Data
        /// `nonce ‖ ciphertext ‖ tag`, ready for `AES.GCM.SealedBox(combined:)`.
        let sealedCombined: Data
    }

    // MARK: - Parsing

    static func hasFormatSignature(_ data: Data) -> Bool {
        guard data.count >= formatSignatureLength else { return false }
        for index in 0..<formatSignatureLength where data[data.startIndex + index] != formatSignature[index] {
            return false
        }
        return true
    }

    /// Splits a well-formed blob into its salt and sealed remainder. Returns
    /// `nil` when the signature is absent or the blob is too short to hold a
    /// header plus a GCM tag — callers treat that as "not our format" rather
    /// than as an error, because legacy blobs are detected that way.
    static func parse(_ data: Data) -> Parsed? {
        guard hasFormatSignature(data), data.count >= headerSize + gcmTagBytes else {
            return nil
        }
        let saltStart = data.startIndex + formatSignatureLength
        let saltEnd = saltStart + saltLength
        return Parsed(
            salt: data.subdata(in: saltStart..<saltEnd),
            sealedCombined: data.subdata(in: saltEnd..<data.endIndex)
        )
    }

    // MARK: - Seal / open

    /// Seals under a caller-supplied salt and nonce. Password-derived callers
    /// pass the salt they derived the key from; raw-key callers pass filler.
    static func seal(_ plaintext: Data, using key: SymmetricKey, salt: Data, iv: Data) throws -> Data {
        do {
            let nonce = try AES.GCM.Nonce(data: iv)
            let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
            guard let combined = sealed.combined else {
                throw VaultCryptoEnvelopeError.encryptionFailed
            }
            var output = Data(capacity: formatSignatureLength + salt.count + combined.count)
            output.append(contentsOf: formatSignature)
            output.append(salt)
            output.append(combined)
            return output
        } catch let error as VaultCryptoEnvelopeError {
            throw error
        } catch {
            logger.error("AES-GCM encryption failed: \(error.localizedDescription, privacy: .public)")
            throw VaultCryptoEnvelopeError.encryptionFailed
        }
    }

    /// Seals under a fresh random salt and nonce. For raw-key payloads, where
    /// the salt carries no meaning and nothing needs to reproduce it.
    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        try seal(
            plaintext,
            using: key,
            salt: try randomBytes(count: saltLength),
            iv: try randomBytes(count: ivLength)
        )
    }

    static func open(_ parsed: Parsed, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: parsed.sealedCombined)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            // Expected on a wrong key or a tampered blob — GCM authentication is
            // what tells those apart from a correct open, so this is not
            // necessarily a fault.
            logger.debug("AES-GCM open failed: \(error.localizedDescription, privacy: .public)")
            throw VaultCryptoEnvelopeError.decryptionFailed
        }
    }

    // MARK: - Keys

    static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: keyLengthBytes)

        let status = salt.withUnsafeBytes { saltPtr -> Int32 in
            guard let saltBase = saltPtr.bindMemory(to: UInt8.self).baseAddress else {
                return Int32(kCCParamError)
            }
            return CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes,
                passwordBytes.count,
                saltBase,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                pbkdf2Iterations,
                &derived,
                keyLengthBytes
            )
        }

        guard status == kCCSuccess else {
            logger.error("PBKDF2 key derivation failed: status=\(status, privacy: .public)")
            throw VaultCryptoEnvelopeError.keyDerivationFailed
        }
        return SymmetricKey(data: Data(derived))
    }

    static func randomKey() throws -> SymmetricKey {
        SymmetricKey(data: try randomBytes(count: keyLengthBytes))
    }

    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            logger.error("SecRandomCopyBytes failed: status=\(status, privacy: .public)")
            throw VaultCryptoEnvelopeError.randomGenerationFailed
        }
        return Data(bytes)
    }
}
