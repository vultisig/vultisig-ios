//
//  BiometricUnlockStoreTests.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest
@testable import VultisigApp

/// Every test here pins one of two properties: **the shortcut fails closed**,
/// and **it only ever hands back a key that belongs to the wrapper on disk.**
///
/// Real biometry cannot be driven from a test bundle, which is why the Keychain
/// access sits behind a seam. A biometric lock that fails *open* is worse than no
/// lock at all, and shipping one is a mistake this org has already made once — so
/// what is verified is that no failure path returns a key.
final class BiometricUnlockStoreTests: XCTestCase {

    private var keychain: FakeBiometricKeychain!
    private var sut: BiometricUnlockStore!
    /// Available unless a test says otherwise, so every case that is not about
    /// availability reads exactly as it did before this seam existed.
    private var availability: BiometricAvailability = .available

    /// Stands in for the passcode-wrapped data key the copy is bound to. Only
    /// its bytes matter here — the store digests them, it never unwraps them.
    private let wrapper = Data("wrapped-key-one".utf8)
    private let otherWrapper = Data("wrapped-key-two".utf8)

    override func setUp() {
        super.setUp()
        keychain = FakeBiometricKeychain()
        availability = .available
        sut = BiometricUnlockStore(
            keychain: keychain,
            biometryAvailability: { [unowned self] in self.availability }
        )
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
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)

        XCTAssertTrue(sut.isEnabled)
    }

    func testEnableSurfacesAStorageFailure() throws {
        keychain.storeError = BiometricUnlockError.storageFailed

        XCTAssertThrowsError(try sut.enable(dataKey: try makeKey(), boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .storageFailed)
        }
        XCTAssertFalse(sut.isEnabled)
    }

    /// The reported bug: a device with nothing enrolled refused the switch and
    /// said nothing. It has to refuse — but as its own error, so the screen can
    /// tell the user what to go and do.
    func testEnableRefusesWithItsOwnErrorWhenNothingIsEnrolled() throws {
        availability = .notEnrolled

        XCTAssertThrowsError(try sut.enable(dataKey: try makeKey(), boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .notEnrolled)
        }
        XCTAssertFalse(sut.isEnabled)
    }

    func testEnableRefusesWhenBiometryIsUnavailable() throws {
        availability = .unavailable

        XCTAssertThrowsError(try sut.enable(dataKey: try makeKey(), boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .unavailable)
        }
        XCTAssertFalse(sut.isEnabled)
    }

    /// Availability is checked *before* the write, not after it fails. A refusal
    /// that had already touched the Keychain would have deleted whatever was
    /// there — `enable` removes before it adds — and left the user with the
    /// shortcut they had turned on earlier silently gone.
    func testAnUnavailableDeviceLeavesAnExistingCopyAlone() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)
        availability = .notEnrolled

        XCTAssertThrowsError(try sut.enable(dataKey: try makeKey(), boundTo: wrapper))
        XCTAssertTrue(sut.isEnabled, "the copy that was already there survives a refusal")
    }

    /// The residual, pinned rather than claimed away. The preflight only moves
    /// the refusals it can *see coming*; the delete-then-add is not atomic, so
    /// enrolment changing in the gap — or the Keychain failing for its own
    /// reasons — still loses an existing copy.
    ///
    /// Left as it is deliberately. Restoring it would mean reading the old blob
    /// out before deleting, which means a biometric prompt on a path that is
    /// documented not to need one, and the whole loss is an *optional shortcut*:
    /// the passcode-wrapped copy is untouched and still opens everything. What
    /// must not happen is discovering this from a bug report, so it is a test.
    func testAStoreFailureAfterTheDeleteStillCostsTheExistingCopy() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)
        keychain.storeError = BiometricUnlockError.storageFailed

        XCTAssertThrowsError(try sut.enable(dataKey: try makeKey(), boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .storageFailed)
        }
        XCTAssertFalse(sut.isEnabled, "known residual: the delete already happened")
    }

    func testDisableRemovesTheKey() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)

        try sut.disable()

        XCTAssertFalse(sut.isEnabled)
    }

    /// A survivor holds the same data key, so it would quietly work again the
    /// next time a passcode is set — an enablement the user never made.
    func testDisableThrowsWhenTheCopyCannotBeRemoved() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)
        keychain.deleteError = BiometricUnlockError.storageFailed

        XCTAssertThrowsError(try sut.disable()) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .storageFailed)
        }
        XCTAssertTrue(sut.isEnabled, "The copy is still there and must be reported as such")
    }

    /// The whole point of storing the binding rather than reading it back: a
    /// passcode change rewraps the key, and rebinding must not cost a prompt.
    func testStoringDoesNotPromptForBiometrics() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)
        try sut.enable(dataKey: try makeKey(), boundTo: otherWrapper)

        XCTAssertEqual(keychain.readCount, 0)
    }

    // MARK: - The happy path

    func testUnlockReturnsTheStoredKey() throws {
        let key = try makeKey()
        try sut.enable(dataKey: key, boundTo: wrapper)

        let unlocked = try sut.unlock(reason: "test", boundTo: wrapper)

        XCTAssertEqual(raw(unlocked), raw(key))
    }

    // MARK: - The binding

    /// The fund-loss case. A copy from an earlier install holds key A while the
    /// wrapper on disk holds key B; nothing else can detect that, because the
    /// wrapper cannot be unwrapped without the passcode and a pending store may
    /// have no sealed share to test against. Adopting A would let the resume
    /// sweep seal every share under a key nothing wraps.
    func testUnlockRefusesACopyBoundToAnotherWrapper() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)

        XCTAssertThrowsError(try sut.unlock(reason: "test", boundTo: otherWrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .supersededCopy)
        }
    }

    /// A shortcut that can only ever fail is worse than none: it advertises
    /// itself as enabled in Settings and prompts for a face that leads nowhere.
    func testUnlockRemovesACopyBoundToAnotherWrapper() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)

        _ = try? sut.unlock(reason: "test", boundTo: otherWrapper)

        XCTAssertFalse(sut.isEnabled)
    }

    /// Rebinding is what a passcode change does, and it has to make the copy
    /// usable against the new wrapper and only that one.
    func testRebindingMovesTheCopyToTheNewWrapper() throws {
        let key = try makeKey()
        try sut.enable(dataKey: key, boundTo: wrapper)

        try sut.enable(dataKey: key, boundTo: otherWrapper)

        XCTAssertEqual(raw(try sut.unlock(reason: "test", boundTo: otherWrapper)), raw(key))
    }

    // MARK: - Every failure must throw, never return a key

    func testUnlockThrowsWhenNotEnabled() {
        XCTAssertThrowsError(try sut.unlock(reason: "test", boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .notEnabled)
        }
    }

    func testUnlockThrowsWhenCancelled() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)
        keychain.readError = BiometricUnlockError.cancelled

        XCTAssertThrowsError(try sut.unlock(reason: "test", boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .cancelled)
        }
    }

    func testUnlockThrowsWhenBiometryIsUnavailable() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)
        keychain.readError = BiometricUnlockError.unavailable

        XCTAssertThrowsError(try sut.unlock(reason: "test", boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .unavailable)
        }
    }

    /// What `.biometryCurrentSet` produces when a new face or finger is enrolled:
    /// the item is gone, and enrolment must not inherit access.
    func testUnlockThrowsWhenEnrolmentChangedAndTheItemVanished() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)
        keychain.readError = BiometricUnlockError.notEnabled

        XCTAssertThrowsError(try sut.unlock(reason: "test", boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .notEnabled)
        }
    }

    func testUnlockThrowsOnAnUnexpectedError() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)
        keychain.readError = CocoaError(.fileReadUnknown)

        XCTAssertThrowsError(try sut.unlock(reason: "test", boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .failed)
        }
    }

    /// A stored blob of the wrong shape cannot open anything, so the shortcut is
    /// removed rather than left in place to fail forever. The passcode is
    /// unaffected. The bare 32 bytes are what a copy written before the binding
    /// existed would look like.
    func testUnlockRejectsAndRemovesAMalformedKey() throws {
        keychain.stored = Data(repeating: 0x01, count: VaultCryptoEnvelope.keyLengthBytes)

        XCTAssertThrowsError(try sut.unlock(reason: "test", boundTo: wrapper)) { error in
            XCTAssertEqual(error as? BiometricUnlockError, .malformedCopy)
        }
        XCTAssertFalse(sut.isEnabled, "A key that cannot work should not be left behind")
    }

    func testExistenceCheckDoesNotReadTheKey() throws {
        try sut.enable(dataKey: try makeKey(), boundTo: wrapper)

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

    /// An add, not an upsert — `SecItemAdd` answers `errSecDuplicateItem` over
    /// an existing item, so a fake that overwrote would hide the one bug this
    /// seam exists to expose.
    func store(_ data: Data, account _: String) throws {
        if let storeError { throw storeError }
        guard stored == nil else { throw BiometricUnlockError.storageFailed }
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
