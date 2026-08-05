//
//  KeyshareInstallReconcilerTests.swift
//  VultisigAppTests
//

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
    private var coordinator: KeyshareWriteCoordinator!
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

        coordinator = KeyshareWriteCoordinator()
        sut = KeyshareInstallReconciler(
            keychain: keychain,
            keyStore: keyStore,
            lockService: lockService,
            coordinator: coordinator,
            defaults: defaults
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        coordinator = nil
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
        XCTAssertEqual(keychain.getPasscodeAttemptState(), .absent, "A new install must not start inside a lockout")
        XCTAssertEqual(
            keychain.getLastMigratedVersion(),
            .present(4),
            "Ordinary migrations are none of this type's business and must not be made to re-run"
        )
    }

    /// The attempt counter is inherited on its own when the previous install
    /// was mid-lockout, and keeping it would start a new install inside a
    /// throttle guarding a passcode that no longer exists.
    func testANewContainerClearsAnInheritedAttemptCounter() {
        keychain.setPasscodeAttemptState(attemptState)

        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keychain.getPasscodeAttemptState(), .absent)
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

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
        XCTAssertEqual(lockService.mode, .deviceAuth)
    }

    /// The acceptance test, asserted rather than argued: someone who never sets
    /// a passcode must see **no** launch-time Keychain mutation. Clearing an
    /// artifact that was never there still issues a `SecItemDelete` and its
    /// read-back per item, and no assertion on stored values can tell that apart
    /// from doing nothing — hence the write log.
    func testAFirstEverInstallWritesNothingToTheKeychain() {
        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keychain.writes, [])
    }

    /// The other half of the same rule, and the reason an unreadable Keychain is
    /// a *deferral* rather than either answer. Skipping the clear would set the
    /// marker, so the inherited passcode would survive forever; running it would
    /// issue deletes on a first-ever install whose Keychain merely stuttered,
    /// which is the launch-time mutation the acceptance test forbids. Neither is
    /// acceptable, so nothing is written and the next launch decides with an
    /// answer.
    func testAnUnreadableKeychainDefersTheClearWithoutWritingAnything() {
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keychain.writes, [], "an unreadable Keychain must not be answered with writes")

        // A deferral, not a decision: once the item can be read, the clear runs.
        keychain.wrappedKeyshareDataKeyResult = .present(wrappedBlob)
        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
    }

    /// A store that cannot be read is not an occupied one. Treating it as
    /// occupied wrote the marker, and the marker is permanent — so a genuinely
    /// new container whose store happened to be unreadable at launch would keep
    /// the previous install's wrapped key for good: a passcode gate that cannot
    /// be opened and cannot be reinstalled away, which is the exact failure this
    /// type exists to prevent.
    func testAnUnreadableStoreDefersReconciliationRatherThanRetiringIt() throws {
        try keyStore.storeWrappedDataKey(wrappedBlob)
        keychain.resetWrites()

        sut.reconcile(occupancy: .unknown)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .present(wrappedBlob), "nothing is decided yet")
        XCTAssertEqual(keychain.writes, [])

        sut.reconcile(occupancy: .empty)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent, "the deferred launch must still clear")
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
        try keyStore.storeWrappedDataKey(wrappedBlob)
        keychain.setLastMigratedVersion(4)

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(
            keyStore.loadWrappedDataKey(),
            .present(wrappedBlob),
            "The key every sealed share depends on must survive"
        )
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

    func testAWrappedKeyRestoresPasscodeMode() throws {
        sut.reconcile(isStoreEmpty: false)
        lockService.mode = .deviceAuth
        try keyStore.storeWrappedDataKey(wrappedBlob)

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(lockService.mode, .passcode, "Key material must never be locked with no way to ask for it")
    }

    /// The inverse, and the half that keeps a user from being locked out. A
    /// passcode mode with no wrapper behind it is a gate `unlock` can never
    /// satisfy — there is nothing to verify a passcode against — so a confirmed
    /// absence takes it back down.
    func testAPasscodeModeWithNoWrappedKeyFallsBackToDeviceAuth() {
        lockService.mode = .passcode

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(lockService.mode, .deviceAuth)
    }

    /// Only a *confirmed* absence, though: taking an unreadable Keychain for an
    /// empty one would remove a real passcode from in front of real key material.
    func testAnUnreadableWrappedKeyDoesNotTakeThePasscodeGateDown() {
        lockService.mode = .passcode
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        sut.reconcile(isStoreEmpty: false)

        XCTAssertEqual(lockService.mode, .passcode)
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

    // MARK: - Serialization

    /// Launch reconciliation deletes and re-decides exactly the state a passcode
    /// set or removal is moving, so it has to be indivisible against one.
    /// Without the lease, a launch landing between `setPasscode` making its
    /// wrapper durable and adopting the key would delete that wrapper and mark
    /// the container done — leaving the key live in memory with nothing on disk
    /// that wraps it, and every share sealed afterwards unreadable.
    func testReconciliationIsSkippedWhileAPasscodeTransitionIsHeld() throws {
        try keyStore.storeWrappedDataKey(wrappedBlob)
        lockService.mode = .deviceAuth
        keychain.resetWrites()
        let lease = try coordinator.beginTransition()
        defer { coordinator.end(lease) }

        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .present(wrappedBlob), "a wrapper mid-transition must survive")
        XCTAssertEqual(keychain.writes, [])
        XCTAssertEqual(lockService.mode, .deviceAuth, "the mode must not be decided from a snapshot a transition is changing")
    }

    /// And the skip leaves the container unmarked, so the next launch reconciles
    /// it properly rather than treating the skip as done.
    func testASkippedReconciliationIsRetriedOnTheNextLaunch() throws {
        try keyStore.storeWrappedDataKey(wrappedBlob)
        let lease = try coordinator.beginTransition()
        sut.reconcile(isStoreEmpty: true)
        // Without the lease the wrapper would already be gone here, and the
        // assertion below would pass over a reconciliation that never skipped.
        XCTAssertEqual(keyStore.loadWrappedDataKey(), .present(wrappedBlob))
        coordinator.end(lease)

        sut.reconcile(isStoreEmpty: true)

        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
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
