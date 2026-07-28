//
//  KeyshareKeyStoreTests.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest
@testable import VultisigApp

final class KeyshareKeyStoreTests: XCTestCase {

    private var keychain: MockKeychainService!
    private var sut: DefaultKeyshareKeyStore!

    override func setUp() {
        super.setUp()
        keychain = MockKeychainService()
        sut = DefaultKeyshareKeyStore(keychain: keychain)
    }

    override func tearDown() {
        sut = nil
        keychain = nil
        super.tearDown()
    }

    // MARK: - Data key

    func testGenerateDataKeyIsCorrectLengthAndRandom() throws {
        let first = try sut.generateDataKey()
        let second = try sut.generateDataKey()

        XCTAssertEqual(first.bitCount, VaultCryptoEnvelope.keyLengthBytes * 8)
        XCTAssertNotEqual(first.testRawRepresentation, second.testRawRepresentation)
    }

    func testStoreAndLoadDataKeyRoundTrip() throws {
        let key = try sut.generateDataKey()

        try sut.storeDataKey(key)

        XCTAssertEqual(sut.loadDataKey()?.testRawRepresentation, key.testRawRepresentation)
    }

    func testLoadDataKeyIsNilWhenAbsent() {
        XCTAssertNil(sut.loadDataKey())
    }

    func testDeleteDataKeyRemovesIt() throws {
        try sut.storeDataKey(try sut.generateDataKey())

        try sut.deleteDataKey()

        XCTAssertNil(sut.loadDataKey())
    }

    /// The read-back guard: a Keychain that silently drops the write must not
    /// leave the caller believing the key is durable, because the next step is
    /// encrypting key shares against it.
    func testStoreDataKeyThrowsWhenKeychainDropsTheWrite() throws {
        keychain.dropsKeyshareDataKeyWrites = true
        let key = try sut.generateDataKey()

        XCTAssertThrowsError(try sut.storeDataKey(key)) { error in
            XCTAssertEqual(error as? KeyshareKeyStoreError, .persistenceFailed)
        }
    }

    func testLoadDataKeyIsNilWhenStoredBlobHasWrongLength() {
        keychain.setKeyshareDataKey(Data(repeating: 0x01, count: 16))

        XCTAssertNil(sut.loadDataKey())
    }

    // MARK: - Wrapped data key

    func testStoreAndLoadWrappedDataKeyRoundTrip() throws {
        let blob = Data(repeating: 0x07, count: 64)

        try sut.storeWrappedDataKey(blob)

        XCTAssertEqual(sut.loadWrappedDataKey(), blob)
    }

    func testDeleteWrappedDataKeyRemovesIt() throws {
        try sut.storeWrappedDataKey(Data(repeating: 0x07, count: 64))

        try sut.deleteWrappedDataKey()

        XCTAssertNil(sut.loadWrappedDataKey())
    }

    // MARK: - Passcode wrapping

    func testWrapUnwrapRoundTrip() async throws {
        let key = try sut.generateDataKey()

        let wrapped = try await sut.wrap(key, passcode: "12345")
        let unwrapped = try await sut.unwrap(wrapped, passcode: "12345")

        XCTAssertEqual(unwrapped.testRawRepresentation, key.testRawRepresentation)
    }

    func testUnwrapWithWrongPasscodeFails() async throws {
        let key = try sut.generateDataKey()
        let wrapped = try await sut.wrap(key, passcode: "12345")

        do {
            _ = try await sut.unwrap(wrapped, passcode: "54321")
            XCTFail("Expected unwrap to fail with the wrong passcode")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .wrongPasscode)
        }
    }

    func testUnwrapRejectsTamperedBlob() async throws {
        let key = try sut.generateDataKey()
        var wrapped = try await sut.wrap(key, passcode: "12345")
        wrapped[wrapped.index(before: wrapped.endIndex)] ^= 0xFF

        do {
            _ = try await sut.unwrap(wrapped, passcode: "12345")
            XCTFail("Expected unwrap to reject a tampered blob")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .wrongPasscode)
        }
    }

    /// Unlike the key-share path, the wrapping key IS derived from the salt, so
    /// corrupting it yields a different key and the tag stops matching.
    func testUnwrapRejectsTamperedSalt() async throws {
        let key = try sut.generateDataKey()
        var wrapped = try await sut.wrap(key, passcode: "12345")
        wrapped[wrapped.startIndex + VaultCryptoEnvelope.formatSignatureLength] ^= 0xFF

        do {
            _ = try await sut.unwrap(wrapped, passcode: "12345")
            XCTFail("Expected unwrap to reject a tampered salt")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .wrongPasscode)
        }
    }

    func testUnwrapRejectsBlobWithoutFormatSignature() async {
        do {
            _ = try await sut.unwrap(Data(repeating: 0x00, count: 64), passcode: "12345")
            XCTFail("Expected unwrap to reject a blob with no signature")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .malformedWrappedKey)
        }
    }

    func testWrapIsNonDeterministic() async throws {
        let key = try sut.generateDataKey()

        let first = try await sut.wrap(key, passcode: "12345")
        let second = try await sut.wrap(key, passcode: "12345")

        XCTAssertNotEqual(first, second, "Each wrap must use a fresh salt and nonce")
    }

    /// The whole point of the indirection: rewrapping under a new passcode
    /// yields a key that opens the same shares, so no share is ever rewritten.
    func testRewrappingUnderNewPasscodeYieldsTheSameDataKey() async throws {
        let key = try sut.generateDataKey()
        let original = try await sut.wrap(key, passcode: "12345")

        let opened = try await sut.unwrap(original, passcode: "12345")
        let rewrapped = try await sut.wrap(opened, passcode: "99999")
        let reopened = try await sut.unwrap(rewrapped, passcode: "99999")

        XCTAssertEqual(reopened.testRawRepresentation, key.testRawRepresentation)
    }
}

private extension SymmetricKey {
    var testRawRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}
