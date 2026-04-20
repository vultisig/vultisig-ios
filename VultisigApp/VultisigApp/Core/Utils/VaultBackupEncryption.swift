import CommonCrypto
import CryptoKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "vault-backup-encryption")

protocol VaultBackupEncryption {
    func encrypt(data: Data, password: String) throws -> Data
    func decrypt(data: Data, password: String) -> Data?
}

enum VaultBackupEncryptionError: Error {
    case keyDerivationFailed
    case randomGenerationFailed
    case encryptionFailed
}

final class Pbkdf2VaultBackupEncryption: VaultBackupEncryption {

    private static let magic: [UInt8] = [0x56, 0x4C, 0x54, 0x02]
    private static let magicSize = 4
    private static let saltLength = 16
    private static let ivLength = 12
    private static let gcmTagBytes = 16
    private static let keyLengthBytes = 32
    private static let iterations: UInt32 = 600_000
    private static let headerSize = magicSize + saltLength + ivLength

    func encrypt(data: Data, password: String) throws -> Data {
        let salt = try randomBytes(count: Self.saltLength)
        let iv = try randomBytes(count: Self.ivLength)
        let key = try deriveKey(password: password, salt: salt)

        do {
            let nonce = try AES.GCM.Nonce(data: iv)
            let sealed = try AES.GCM.seal(data, using: key, nonce: nonce)
            guard let combined = sealed.combined else {
                throw VaultBackupEncryptionError.encryptionFailed
            }
            var output = Data(capacity: Self.magicSize + salt.count + combined.count)
            output.append(contentsOf: Self.magic)
            output.append(salt)
            output.append(combined)
            return output
        } catch let error as VaultBackupEncryptionError {
            throw error
        } catch {
            logger.error("AES-GCM encryption failed: \(error.localizedDescription, privacy: .public)")
            throw VaultBackupEncryptionError.encryptionFailed
        }
    }

    func decrypt(data: Data, password: String) -> Data? {
        if hasMagicPrefix(data) {
            return decryptPbkdf2(data: data, password: password)
        }
        return legacyDecrypt(data: data, password: password)
    }

    private func decryptPbkdf2(data: Data, password: String) -> Data? {
        let minSize = Self.headerSize + Self.gcmTagBytes
        guard data.count >= minSize else {
            logger.warning("PBKDF2 payload too small: \(data.count, privacy: .public) bytes")
            return nil
        }

        let saltStart = Self.magicSize
        let saltEnd = saltStart + Self.saltLength
        let salt = data.subdata(in: saltStart..<saltEnd)
        let sealedCombined = data.subdata(in: saltEnd..<data.count)

        do {
            let key = try deriveKey(password: password, salt: salt)
            let sealedBox = try AES.GCM.SealedBox(combined: sealedCombined)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            logger.error("PBKDF2 decryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func legacyDecrypt(data: Data, password: String) -> Data? {
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            logger.error("Legacy decryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func hasMagicPrefix(_ data: Data) -> Bool {
        guard data.count >= Self.magicSize else { return false }
        for index in 0..<Self.magicSize where data[data.startIndex + index] != Self.magic[index] {
            return false
        }
        return true
    }

    private func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: Self.keyLengthBytes)

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
                Self.iterations,
                &derived,
                Self.keyLengthBytes
            )
        }

        guard status == kCCSuccess else {
            logger.error("PBKDF2 key derivation failed: status=\(status, privacy: .public)")
            throw VaultBackupEncryptionError.keyDerivationFailed
        }
        return SymmetricKey(data: Data(derived))
    }

    private func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            logger.error("SecRandomCopyBytes failed: status=\(status, privacy: .public)")
            throw VaultBackupEncryptionError.randomGenerationFailed
        }
        return Data(bytes)
    }
}
