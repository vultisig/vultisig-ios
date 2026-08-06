//
//  KeyshareCipherTests.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest
@testable import VultisigApp

final class KeyshareCipherTests: XCTestCase {

    private var sut: AesGcmKeyshareCipher!
    private var key: SymmetricKey!

    /// Shaped like a real DKLS share: base64, no prefix.
    private let dklsPlaintext = "eyJrZXlzaGFyZSI6ImV4YW1wbGUifQ=="
    /// Shaped like a real GG20 share: raw JSON.
    private let gg20Plaintext = #"{"PubKey":"02abc","ShareID":{"value":"12345"}}"#

    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = AesGcmKeyshareCipher()
        key = try VaultCryptoEnvelope.randomKey()
    }

    override func tearDown() {
        sut = nil
        key = nil
        super.tearDown()
    }

    // MARK: - Round trip

    func testSealOpenRoundTrip() throws {
        let sealed = try sut.seal(dklsPlaintext, with: key)

        XCTAssertEqual(try sut.open(sealed, with: key), dklsPlaintext)
    }

    func testSealOpenRoundTripForGg20Json() throws {
        let sealed = try sut.seal(gg20Plaintext, with: key)

        XCTAssertEqual(try sut.open(sealed, with: key), gg20Plaintext)
    }

    func testSealOpenRoundTripForEmptyString() throws {
        let sealed = try sut.seal("", with: key)

        XCTAssertEqual(try sut.open(sealed, with: key), "")
    }

    func testSealOpenRoundTripForLargeShare() throws {
        let large = String(repeating: "A", count: 512 * 1024)

        let sealed = try sut.seal(large, with: key)

        XCTAssertEqual(try sut.open(sealed, with: key), large)
    }

    func testSealIsNonDeterministic() throws {
        let first = try sut.seal(dklsPlaintext, with: key)
        let second = try sut.seal(dklsPlaintext, with: key)

        XCTAssertNotEqual(first, second, "Each seal must use a fresh nonce")
    }

    // MARK: - Detection

    func testIsSealedIsFalseForPlaintextDklsShare() {
        XCTAssertFalse(sut.isSealed(dklsPlaintext))
    }

    func testIsSealedIsFalseForPlaintextGg20Share() {
        XCTAssertFalse(sut.isSealed(gg20Plaintext))
    }

    func testIsSealedIsTrueForSealedValue() throws {
        let sealed = try sut.seal(dklsPlaintext, with: key)

        XCTAssertTrue(sut.isSealed(sealed))
    }

    func testOpenRejectsUnsealedValue() {
        XCTAssertThrowsError(try sut.open(dklsPlaintext, with: key)) { error in
            XCTAssertEqual(error as? KeyshareCipherError, .notSealed)
        }
    }

    // MARK: - Rejection

    func testOpenWithWrongKeyFails() throws {
        let sealed = try sut.seal(dklsPlaintext, with: key)
        let otherKey = try VaultCryptoEnvelope.randomKey()

        XCTAssertThrowsError(try sut.open(sealed, with: otherKey)) { error in
            XCTAssertEqual(error as? KeyshareCipherError, .decryptionFailed)
        }
    }

    func testOpenRejectsTamperedCiphertext() throws {
        let sealed = try sut.seal(dklsPlaintext, with: key)
        let tampered = try flipLastByte(of: sealed)

        XCTAssertThrowsError(try sut.open(tampered, with: key)) { error in
            XCTAssertEqual(error as? KeyshareCipherError, .decryptionFailed)
        }
    }

    /// The salt is not covered by the GCM tag, and a key share is sealed under a
    /// raw key that was never derived from it — so the salt is inert filler here
    /// and corrupting it provably cannot change the recovered share. What
    /// protects the share is the ciphertext and tag, exercised above. The salt
    /// only carries meaning where a key is derived from it, which is the wrapped
    /// data key — see `KeyshareKeyStoreTests.testUnwrapRejectsTamperedSalt`.
    func testSaltIsInertForRawKeyPayloads() throws {
        let sealed = try sut.seal(dklsPlaintext, with: key)
        // Salt sits immediately after the 4-byte signature.
        let tampered = try flipByte(of: sealed, at: VaultCryptoEnvelope.formatSignatureLength)

        XCTAssertEqual(try sut.open(tampered, with: key), dklsPlaintext)
    }

    func testOpenRejectsTamperedNonce() throws {
        let sealed = try sut.seal(dklsPlaintext, with: key)
        let nonceStart = VaultCryptoEnvelope.formatSignatureLength + VaultCryptoEnvelope.saltLength
        let tampered = try flipByte(of: sealed, at: nonceStart)

        XCTAssertThrowsError(try sut.open(tampered, with: key)) { error in
            XCTAssertEqual(error as? KeyshareCipherError, .decryptionFailed)
        }
    }

    func testOpenRejectsMalformedBase64() {
        let stored = AesGcmKeyshareCipher.sealedPrefix + "!!!not-base64!!!"

        XCTAssertThrowsError(try sut.open(stored, with: key)) { error in
            XCTAssertEqual(error as? KeyshareCipherError, .malformedBlob)
        }
    }

    func testOpenRejectsTruncatedBlob() throws {
        let sealed = try sut.seal(dklsPlaintext, with: key)
        let blob = try XCTUnwrap(Data(base64Encoded: String(sealed.dropFirst(AesGcmKeyshareCipher.sealedPrefix.count))))
        let truncated = AesGcmKeyshareCipher.sealedPrefix
            + blob.prefix(VaultCryptoEnvelope.headerSize).base64EncodedString()

        XCTAssertThrowsError(try sut.open(truncated, with: key)) { error in
            XCTAssertEqual(error as? KeyshareCipherError, .malformedBlob)
        }
    }

    func testOpenRejectsBlobWithoutFormatSignature() throws {
        let sealed = try sut.seal(dklsPlaintext, with: key)
        let tampered = try flipByte(of: sealed, at: 0)

        XCTAssertThrowsError(try sut.open(tampered, with: key)) { error in
            XCTAssertEqual(error as? KeyshareCipherError, .malformedBlob)
        }
    }

    // MARK: - Helpers

    private func flipByte(of stored: String, at index: Int) throws -> String {
        let encoded = String(stored.dropFirst(AesGcmKeyshareCipher.sealedPrefix.count))
        var blob = try XCTUnwrap(Data(base64Encoded: encoded))
        blob[blob.startIndex + index] ^= 0xFF
        return AesGcmKeyshareCipher.sealedPrefix + blob.base64EncodedString()
    }

    private func flipLastByte(of stored: String) throws -> String {
        let encoded = String(stored.dropFirst(AesGcmKeyshareCipher.sealedPrefix.count))
        var blob = try XCTUnwrap(Data(base64Encoded: encoded))
        blob[blob.index(before: blob.endIndex)] ^= 0xFF
        return AesGcmKeyshareCipher.sealedPrefix + blob.base64EncodedString()
    }
}
