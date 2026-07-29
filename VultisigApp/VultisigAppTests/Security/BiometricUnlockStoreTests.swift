//
//  BiometricUnlockStoreTests.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest
@testable import VultisigApp

/// Every test here pins the same property: **the shortcut fails closed.**
///
/// Real biometry cannot be driven from a test bundle, which is why the Keychain
/// access sits behind a seam. A biometric lock that fails *open* is worse than no
/// lock at all, and shipping one is a mistake this org has already made once — so
/// what is verified is that no failure path returns a key.
final class BiometricUnlockStoreTests: XCTestCase {

    private var keychain: FakeBiometricKeychain!
    private var sut: BiometricUnlockStore!

    override func setUp() {
        super.setUp()
        keychain = FakeBiometricKeychain()
        sut = BiometricUnlockStore(keychain: keychain)
    }

    override func tearDown() {
        sut = nil
        keychain = nil
        super.tearDown()
    }

    private func makeKey() throws -> SymmetricKey {
        try VaultCryptoEnvelope.randomKey()
    }

    private func raw(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    // MARK: - Enable / disable

    func testNotEnabledByDefault() {
        XCTAssertFalse(sut.isEnabled)
    }

    func testEnableStoresTheKey() throws {
        try sut.enable(dataKey: try makeKey())

        XCTAssertTrue(sut.isEnabled)
    }

    func testEnableSurfacesAStorageFailure() throws {
        keychain.storeError = BiometricUnlockError.storageFailed

        XCTAssertThrowsError(try sut.enable(dataKey: try makeKey())) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .storageFailed)
        }
        XCTAssertFalse(sut.isEnabled)
    }

    func testDisableRemovesTheKey() throws {
        try sut.enable(dataKey: try makeKey())

        try sut.disable()

        XCTAssertFalse(sut.isEnabled)
    }

    /// A survivor holds the same data key, so it would quietly work again the
    /// next time a passcode is set — an enablement the user never made.
    func testDisableThrowsWhenTheCopyCannotBeRemoved() throws {
        try sut.enable(dataKey: try makeKey())
        keychain.deleteError = BiometricUnlockError.storageFailed

        XCTAssertThrowsError(try sut.disable()) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .storageFailed)
        }
        XCTAssertTrue(sut.isEnabled, "The copy is still there and must be reported as such")
    }

    // MARK: - The happy path

    func testUnlockReturnsTheStoredKey() throws {
        let key = try makeKey()
        try sut.enable(dataKey: key)

        let unlocked = try sut.unlock(reason: "test")

        XCTAssertEqual(raw(unlocked), raw(key))
    }

    // MARK: - Every failure must throw, never return a key

    func testUnlockThrowsWhenNotEnabled() {
        XCTAssertThrowsError(try sut.unlock(reason: "test")) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .notEnabled)
        }
    }

    func testUnlockThrowsWhenCancelled() throws {
        try sut.enable(dataKey: try makeKey())
        keychain.readError = BiometricUnlockError.cancelled

        XCTAssertThrowsError(try sut.unlock(reason: "test")) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .cancelled)
        }
    }

    func testUnlockThrowsWhenBiometryIsUnavailable() throws {
        try sut.enable(dataKey: try makeKey())
        keychain.readError = BiometricUnlockError.unavailable

        XCTAssertThrowsError(try sut.unlock(reason: "test")) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .unavailable)
        }
    }

    /// What `.biometryCurrentSet` produces when a new face or finger is enrolled:
    /// the item is gone, and enrolment must not inherit access.
    func testUnlockThrowsWhenEnrolmentChangedAndTheItemVanished() throws {
        try sut.enable(dataKey: try makeKey())
        keychain.readError = BiometricUnlockError.notEnabled

        XCTAssertThrowsError(try sut.unlock(reason: "test")) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .notEnabled)
        }
    }

    func testUnlockThrowsOnAnUnexpectedError() throws {
        try sut.enable(dataKey: try makeKey())
        keychain.readError = CocoaError(.fileReadUnknown)

        XCTAssertThrowsError(try sut.unlock(reason: "test")) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .failed)
        }
    }

    /// A stored blob of the wrong shape cannot open anything, so the shortcut is
    /// removed rather than left in place to fail forever. The passcode is
    /// unaffected.
    func testUnlockRejectsAndRemovesAMalformedKey() throws {
        keychain.stored = Data(repeating: 0x01, count: 16)

        XCTAssertThrowsError(try sut.unlock(reason: "test")) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .failed)
        }
        XCTAssertFalse(sut.isEnabled, "A key that cannot work should not be left behind")
    }

    func testExistenceCheckDoesNotReadTheKey() throws {
        try sut.enable(dataKey: try makeKey())

        _ = sut.isEnabled

        XCTAssertEqual(keychain.readCount, 0, "Checking presence must not prompt for biometrics")
    }
}

/// In-memory stand-in. `exists` deliberately does not go through `read`, mirroring
/// the real implementation's use of `kSecUseAuthenticationUISkip`.
private final class FakeBiometricKeychain: BiometricKeychainProtecting {

    var stored: Data?
    var storeError: Error?
    var readError: Error?
    private(set) var readCount = 0

    func store(_ data: Data, account _: String) throws {
        if let storeError { throw storeError }
        stored = data
    }

    func read(account _: String, prompt _: String) throws -> Data {
        readCount += 1
        if let readError { throw readError }
        guard let stored else { throw BiometricUnlockError.notEnabled }
        return stored
    }

    var deleteError: Error?

    func delete(account _: String) throws {
        if let deleteError { throw deleteError }
        stored = nil
    }

    func exists(account _: String) -> Bool {
        stored != nil
    }
}
