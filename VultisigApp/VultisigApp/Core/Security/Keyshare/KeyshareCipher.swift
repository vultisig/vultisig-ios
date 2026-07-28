//
//  KeyshareCipher.swift
//  VultisigApp
//

import CryptoKit
import Foundation

enum KeyshareCipherError: Error, Equatable {
    case notSealed
    case malformedBlob
    case decryptionFailed
    case invalidPlaintextEncoding
}

/// Seals and opens a single key share for storage at rest.
///
/// Sealed shares are written back into the same `KeyShare.keyshare` field they
/// occupied in plaintext, so the stored value has to say which of the two it is.
/// `sealedPrefix` does that: `:` is outside the base64 alphabet, so a sealed
/// value can never be mistaken for a plaintext DKLS share (base64) or a
/// plaintext GG20 share (JSON). Detection is a pure function of the value —
/// nothing else has to be consulted, and re-sealing an already-sealed share is
/// a no-op rather than a corruption.
protocol KeyshareCipher {
    func seal(_ plaintext: String, with key: SymmetricKey) throws -> String
    func open(_ stored: String, with key: SymmetricKey) throws -> String
    func isSealed(_ stored: String) -> Bool
}

struct AesGcmKeyshareCipher: KeyshareCipher {

    static let sealedPrefix = "vlt2:"

    func isSealed(_ stored: String) -> Bool {
        stored.hasPrefix(Self.sealedPrefix)
    }

    func seal(_ plaintext: String, with key: SymmetricKey) throws -> String {
        let blob = try VaultCryptoEnvelope.seal(Data(plaintext.utf8), using: key)
        return Self.sealedPrefix + blob.base64EncodedString()
    }

    func open(_ stored: String, with key: SymmetricKey) throws -> String {
        guard isSealed(stored) else {
            throw KeyshareCipherError.notSealed
        }

        let encoded = String(stored.dropFirst(Self.sealedPrefix.count))
        guard let blob = Data(base64Encoded: encoded),
              let parsed = VaultCryptoEnvelope.parse(blob) else {
            throw KeyshareCipherError.malformedBlob
        }

        let plaintext: Data
        do {
            plaintext = try VaultCryptoEnvelope.open(parsed, using: key)
        } catch {
            throw KeyshareCipherError.decryptionFailed
        }

        guard let value = String(data: plaintext, encoding: .utf8) else {
            throw KeyshareCipherError.invalidPlaintextEncoding
        }
        return value
    }
}
