//
//  KeyshareKeySessionTests.swift
//  VultisigAppTests
//

import CryptoKit
import Security
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

        XCTAssertEqual(keychain.writes, [], "an install with no passcode must see no Keychain mutation at all")
    }

    /// The whole of the persisted state is whether a wrapped key exists, so an
    /// unreadable Keychain must not be read as "no passcode". `.disabled` is a
    /// licence to write plaintext, and the next `seal` would take it.
    func testAnUnreadableKeychainReportsLockedRatherThanDisabled() {
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)
        let sut = makeSession()

        guard case .locked = sut.currentState() else {
            return XCTFail("Expected .locked when the Keychain cannot be read")
        }
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

    /// The unwrapped item no longer participates in the state at all: a share is
    /// sealed if and only if a passcode is set, and the wrapped key is the only
    /// evidence of a passcode. Pinned rather than left implicit, because it is
    /// the visible consequence of collapsing the state read — a store holding a
    /// clear key and nothing else reads as having no passcode.
    func testAnUnwrappedKeyAloneIsNotAPasscode() throws {
        try store.storeDataKey(try store.generateDataKey())
        let sut = makeSession()

        guard case .disabled = sut.currentState() else {
            return XCTFail("Expected .disabled — only a wrapped key means a passcode is set")
        }
    }

    /// The key is held in memory once adopted, so the read path does not pay a
    /// Keychain round trip per share inside TSS keygen and keysign.
    func testAnAdoptedKeyIsCachedRatherThanRereadPerCall() throws {
        let key = try store.generateDataKey()
        let sut = makeSession()
        sut.adopt(key)

        keychain.resetWrites()
        _ = sut.currentState()
        _ = sut.currentState()

        guard case .unlocked(let held) = sut.currentState() else {
            return XCTFail("Expected the adopted key to stay in memory")
        }
        XCTAssertEqual(held.testRawRepresentation, key.testRawRepresentation)
        XCTAssertEqual(keychain.writes, [])
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
