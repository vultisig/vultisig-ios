//
//  KeyshareKeySessionTests.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest
@testable import VultisigApp

/// Pins the state machine `KeyshareProtector` now reads by default.
///
/// The headline is the first test: with nothing in the Keychain the session
/// reports `.disabled` and writes nothing, which is what keeps an install that
/// never sets a passcode byte-for-byte identical to one built without this
/// feature.
final class KeyshareKeySessionTests: XCTestCase {

    private var keychain: MockKeychainService!
    private var store: DefaultKeyshareKeyStore!

    override func setUp() {
        super.setUp()
        keychain = MockKeychainService()
        store = DefaultKeyshareKeyStore(keychain: keychain)
    }

    override func tearDown() {
        store = nil
        keychain = nil
        super.tearDown()
    }

    private func makeSession() -> KeyshareKeySession {
        KeyshareKeySession(store: store)
    }

    // MARK: - No passcode

    func testEmptyKeychainReportsDisabled() {
        let sut = makeSession()

        guard case .disabled = sut.currentState() else {
            return XCTFail("Expected .disabled with no key of either form")
        }
    }

    func testReadingStateWritesNothingToTheKeychain() {
        let sut = makeSession()

        _ = sut.currentState()
        _ = sut.currentState()

        XCTAssertEqual(keychain.getKeyshareDataKey(), .absent)
        XCTAssertEqual(keychain.getWrappedKeyshareDataKey(), .absent)
    }

    // MARK: - Wrapped key present

    func testWrappedKeyWithNoOpenedKeyReportsLocked() throws {
        try store.storeWrappedDataKey(Data([0x01, 0x02, 0x03]))
        let sut = makeSession()

        guard case .locked = sut.currentState() else {
            return XCTFail("Expected .locked while only a wrapped key exists")
        }
    }

    // MARK: - Key in hand

    func testAdoptedKeyReportsUnlockedWithoutTouchingTheKeychain() throws {
        let key = try store.generateDataKey()
        try store.storeWrappedDataKey(Data([0x01]))
        let sut = makeSession()

        sut.adopt(key)

        guard case .unlocked(let held) = sut.currentState() else {
            return XCTFail("Expected .unlocked after adopt")
        }
        XCTAssertEqual(held.testRawRepresentation, key.testRawRepresentation)
    }

    func testAdoptedKeyWinsOverAWrappedOne() throws {
        try store.storeWrappedDataKey(Data([0x01]))
        let sut = makeSession()
        XCTAssertTrue(sut.currentState().isLocked)

        sut.adopt(try store.generateDataKey())

        XCTAssertFalse(sut.currentState().isLocked)
    }

    /// The unwrapped item is legacy — nothing writes one — but while the API
    /// exists an install holding one must be reported as unlocked rather than as
    /// unprotected, or its sealed shares would look like plaintext.
    func testAnUnwrappedKeyIsStillRecognisedAndCached() throws {
        let key = try store.generateDataKey()
        try store.storeDataKey(key)
        let sut = makeSession()

        guard case .unlocked(let held) = sut.currentState() else {
            return XCTFail("Expected .unlocked from an unwrapped key")
        }
        XCTAssertEqual(held.testRawRepresentation, key.testRawRepresentation)

        // Cached, so the read path does not pay a Keychain round trip per share.
        keychain.setKeyshareDataKey(nil)
        guard case .unlocked = sut.currentState() else {
            return XCTFail("Expected the key to be held in memory after the first read")
        }
    }

    // MARK: - Clearing

    func testClearForgetsTheKeyAndFallsBackToTheStore() throws {
        try store.storeWrappedDataKey(Data([0x01]))
        let sut = makeSession()
        sut.adopt(try store.generateDataKey())

        sut.clear()

        guard case .locked = sut.currentState() else {
            return XCTFail("Expected .locked once the opened key is forgotten")
        }
    }

    func testClearOnAnEmptyStoreLandsBackOnDisabled() throws {
        let sut = makeSession()
        sut.adopt(try store.generateDataKey())

        sut.clear()

        guard case .disabled = sut.currentState() else {
            return XCTFail("Expected .disabled once the opened key is forgotten")
        }
    }

    // MARK: - Concurrency

    /// Reached synchronously from TSS callbacks on arbitrary threads, so the
    /// state read has to be safe under contention.
    func testConcurrentStateReadsAreSafe() throws {
        try store.storeWrappedDataKey(Data([0x01]))
        let sut = makeSession()

        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            if iteration % 20 == 0 {
                sut.clear()
            } else {
                _ = sut.currentState()
            }
        }

        guard case .locked = sut.currentState() else {
            return XCTFail("Expected .locked after concurrent reads with no key adopted")
        }
    }
}

private extension KeyshareProtectionState {
    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }
}

private extension SymmetricKey {
    var testRawRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}
