//
//  KeyshareInstallReconcilerTests.swift
//  VultisigAppTests
//

import CryptoKit
import Security
import XCTest
@testable import VultisigApp

/// The Keychain outlives the app while `UserDefaults` does not, so a reinstall
/// inherits key material the container knows nothing about. These pin both
/// directions of that: the inherited state is cleared when the container is new,
/// and it is never touched when anything could still depend on it.
final class KeyshareInstallReconcilerTests: XCTestCase {

    private var keychain: MockKeychainService!
    private var keyStore: DefaultKeyshareKeyStore!
    private var lockService: AppLockService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: KeyshareInstallReconciler!

    private let wrappedBlob = Data(repeating: 7, count: 60)
    private let attemptState = Data(repeating: 3, count: 16)

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "KeyshareInstallReconcilerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        keychain = MockKeychainService()
        keyStore = DefaultKeyshareKeyStore(keychain: keychain)
        lockService = AppLockService(defaults: defaults)

        sut = KeyshareInstallReconciler(
            keychain: keychain,
            keyStore: keyStore,
            lockService: lockService,
            defaults: defaults
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        lockService = nil
        keyStore = nil
        keychain = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - A new container

    /// The reported failure: passcode set, app deleted, app reinstalled. The
    /// wrapped key survives while the lock mode does not, so the passcode screen
    /// is never shown and nothing can ever be sealed again.
    func testANewContainerClearsAPasscodeInheritedFromAPreviousInstall() throws {
        try keyStore.storeWrappedDataKey(wrappedBlob)
        keychain.setPasscodeAttemptState(attemptState)
        keychain.setLastMigratedVersion(4)

        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent, "The inherited passcode must not survive a new container")
        XCTAssertAbsent(keyStore.loadDataKey())
        XCTAssertEqual(keychain.getPasscodeAttemptState(), .absent, "A new install must not start inside a lockout")
        XCTAssertEqual(
            keychain.getLastMigratedVersion(),
            .present(4),
            "Ordinary migrations are none of this type's business and must not be made to re-run"
        )
    }

    func testANewContainerClearsAnInheritedClearDataKey() throws {
        try keyStore.storeDataKey(SymmetricKey(size: .bits256))

        sut.reconcile(isStoreEmpty: true)

        XCTAssertAbsent(keyStore.loadDataKey())
    }

    /// The acceptance test in one assertion: someone who never set a passcode
    /// must see no launch-time Keychain write they would not have seen before
    /// this feature existed, and re-running every ordinary migration on a fresh
    /// container is exactly such a write.
    func testANewContainerLeavesTheMigrationVersionAlone() throws {
        try keyStore.storeWrappedDataKey(wrappedBlob)
        keychain.setLastMigratedVersion(4)

        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
        XCTAssertEqual(keychain.getLastMigratedVersion(), .present(4))
    }

    func testAFirstEverInstallHasNothingToClear() {
        sut.reconcile(isStoreEmpty: true)

        XCTAssertAbsent(keyStore.loadDataKey())
        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
        XCTAssertEqual(lockService.mode, .deviceAuth)
    }

    /// The acceptance test, asserted rather than argued: someone who never sets
    /// a passcode must see **no** launch-time Keychain mutation. Clearing an
    /// artifact that was never there still issues three `SecItemDelete` calls
    /// and three read-backs, and no assertion on stored values can tell that
    /// apart from doing nothing — hence the write log.
    func testAFirstEverInstallWritesNothingToTheKeychain() {
        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keychain.writes, [])
    }

    /// The other half of the same rule: skipping the clear is only allowed on a
    /// *confirmed* absence. Skipping on a read failure would also set the marker,
    /// so the inherited passcode would survive forever.
    func testAnUnreadableKeychainIsNotMistakenForNothingToClear() {
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        sut.reconcile(isStoreEmpty: true)

        XCTAssertTrue(
            keychain.writes.contains("wrappedKeyshareDataKey"),
            "an item that could not be read may well be there, so the clear must still run"
        )
    }

    /// The marker is the only evidence a container has been seen before, and it
    /// is written only when the clear reports success. A clear that reported
    /// failure without failing would leave the marker unset and repeat the
    /// destructive path on every single launch afterwards — so a passcode set
    /// after the first launch would be silently removed on the second.
    func testASuccessfulClearMarksTheContainerSoItIsNeverClearedAgain() throws {
        try keyStore.storeWrappedDataKey(wrappedBlob)

        sut.reconcile(isStoreEmpty: true)
        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)

        try keyStore.storeWrappedDataKey(wrappedBlob)
        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(
            keyStore.loadWrappedDataKey(),
            .present(wrappedBlob),
            "the container was reconciled on the previous launch and must not be purged again"
        )
    }

    // MARK: - Containers that must never be purged

    /// The one that would cost funds. Every existing user reaches the marker
    /// check for the first time on the launch that introduces it, with a full
    /// store — clearing their key would orphan every sealed share.
    func testAStoreWithVaultsIsNeverPurged() throws {
        try keyStore.storeDataKey(SymmetricKey(size: .bits256))
        let storedKey = keychain.getKeyshareDataKey()
        keychain.setLastMigratedVersion(4)

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(keychain.getKeyshareDataKey(), storedKey, "The key every sealed share depends on must survive")
        XCTAssertEqual(keychain.getLastMigratedVersion(), .present(4), "An upgrading user must not re-run every migration")
    }

    /// Deleting every vault is not the same as reinstalling. Without the marker
    /// this would silently remove a passcode the user still expects to have.
    func testDeletingEveryVaultDoesNotRemoveThePasscode() throws {
        // A launch with vaults present marks the container as known.
        sut.reconcile(isStoreEmpty: false)

        try keyStore.storeWrappedDataKey(wrappedBlob)
        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .present(wrappedBlob))
    }

    // MARK: - Lock mode invariant

    func testAWrappedKeyWithoutAClearOneRestoresPasscodeMode() throws {
        sut.reconcile(isStoreEmpty: false)
        lockService.mode = .deviceAuth
        try keyStore.storeWrappedDataKey(wrappedBlob)

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(lockService.mode, .passcode, "Key material must never be locked with no way to ask for it")
    }

    func testAClearDataKeyLeavesTheLockModeAlone() throws {
        lockService.mode = .deviceAuth
        try keyStore.storeDataKey(SymmetricKey(size: .bits256))

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(lockService.mode, .deviceAuth)
    }

    /// Fail closed, but in the direction that keeps the app usable: a gate with
    /// no wrapper behind it has nothing for `unlock` to verify against, so it
    /// could never be opened.
    func testAnUnreadableWrappedKeyDoesNotManufactureAPasscodeGate() {
        lockService.mode = .deviceAuth
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(lockService.mode, .deviceAuth)
    }

    /// And the opposite direction on the other read: an unreadable clear key is
    /// not a reason to leave key material with no door in front of it.
    func testAnUnreadableClearKeyDoesNotSuppressTheLockScreen() throws {
        sut.reconcile(isStoreEmpty: false)
        lockService.mode = .deviceAuth
        try keyStore.storeWrappedDataKey(wrappedBlob)
        keychain.keyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(lockService.mode, .passcode)
    }

    // MARK: - Failure

    /// A clear that silently did not happen is the failure shape this whole
    /// feature keeps producing. It must leave the container unmarked so the next
    /// launch tries again, and must still put a lock screen in front of the key
    /// that survived.
    func testAFailedClearIsRetriedOnTheNextLaunch() throws {
        try keyStore.storeWrappedDataKey(wrappedBlob)
        keychain.ignoresWrappedKeyshareDataKeyDeletion = true

        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .present(wrappedBlob))
        XCTAssertEqual(lockService.mode, .passcode, "The surviving key needs a door while the clear is retried")

        keychain.ignoresWrappedKeyshareDataKeyDeletion = false
        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
    }

    func testAFailedAttemptStateClearIsRetried() throws {
        keychain.setPasscodeAttemptState(attemptState)
        keychain.ignoresPasscodeAttemptStateDeletion = true

        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keychain.getPasscodeAttemptState(), .present(attemptState))

        keychain.ignoresPasscodeAttemptStateDeletion = false
        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keychain.getPasscodeAttemptState(), .absent)
    }
}
