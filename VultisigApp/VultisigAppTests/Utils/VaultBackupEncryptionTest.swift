//
//  VaultBackupEncryptionTest.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest
@testable import VultisigApp

final class VaultBackupEncryptionTest: XCTestCase {

    private let magic: [UInt8] = [0x56, 0x4C, 0x54, 0x02]
    private let magicSize = 4
    private let saltLength = 16
    private let ivLength = 12
    private let gcmTagBytes = 16

    private var sut: Pbkdf2VaultBackupEncryption!

    override func setUp() {
        super.setUp()
        sut = Pbkdf2VaultBackupEncryption()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testEncryptDecryptRoundtrip() throws {
        let plaintext = Data("hello vultisig backup".utf8)
        let password = "s3cret-p@ss"

        let encrypted = try sut.encrypt(data: plaintext, password: password)
        let decrypted = sut.decrypt(data: encrypted, password: password)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testWrongPasswordReturnsNil() throws {
        let plaintext = Data("hello vultisig backup".utf8)
        let encrypted = try sut.encrypt(data: plaintext, password: "right-password")

        let decrypted = sut.decrypt(data: encrypted, password: "wrong-password")

        XCTAssertNil(decrypted)
    }

    func testDecryptsLegacyBackup() throws {
        let plaintext = Data("legacy vault".utf8)
        let password = "legacy-password"
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let legacyData = sealed.combined else {
            XCTFail("Failed to seal legacy data")
            return
        }

        let decrypted = sut.decrypt(data: legacyData, password: password)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptedOutputStartsWithMagic() throws {
        let plaintext = Data("something".utf8)
        let encrypted = try sut.encrypt(data: plaintext, password: "pw")

        XCTAssertGreaterThanOrEqual(encrypted.count, magicSize)
        let prefix = Array(encrypted.prefix(magicSize))
        XCTAssertEqual(prefix, magic)
    }

    func testEncryptedOutputHasHeaderAndTag() throws {
        let plaintext = Data("x".utf8)
        let encrypted = try sut.encrypt(data: plaintext, password: "pw")

        let minSize = magicSize + saltLength + ivLength + plaintext.count + gcmTagBytes
        XCTAssertGreaterThanOrEqual(encrypted.count, minSize)
    }

    func testLegacyBackupWithPartialMagicPrefixStillDecrypts() throws {
        // Craft a legacy payload whose sealed blob starts with the first three
        // magic bytes (0x56, 0x4C, 0x54) but a different fourth byte, proving
        // the full 4-byte magic is required for PBKDF2 detection.
        let password = "pw"
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))

        var nonceBytes = [UInt8](repeating: 0, count: 12)
        nonceBytes[0] = 0x56
        nonceBytes[1] = 0x4C
        nonceBytes[2] = 0x54
        nonceBytes[3] = 0xFF
        let nonce = try AES.GCM.Nonce(data: Data(nonceBytes))

        let plaintext = Data("legacy with partial magic prefix".utf8)
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        guard let legacyData = sealed.combined else {
            XCTFail("Failed to seal legacy data")
            return
        }

        XCTAssertEqual(Array(legacyData.prefix(3)), [0x56, 0x4C, 0x54])
        XCTAssertNotEqual(legacyData[3], 0x02)

        let decrypted = sut.decrypt(data: legacyData, password: password)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testTooSmallPbkdf2PayloadReturnsNil() {
        var tiny = Data(magic)
        tiny.append(Data(repeating: 0, count: 5))

        let decrypted = sut.decrypt(data: tiny, password: "pw")

        XCTAssertNil(decrypted)
    }
}
