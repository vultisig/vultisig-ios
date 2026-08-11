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
    private var biometricKeychain: StubBiometricKeychain!
    private var biometrics: BiometricUnlockStore!
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
        biometricKeychain = StubBiometricKeychain()
        // Availability is stated rather than inherited: the default reads this
        // runner's real `LAContext`, which reports nothing enrolled on a
        // simulator, and reconciliation is not about whether biometry works —
        // it is about removing a copy a previous install left behind.
        biometrics = BiometricUnlockStore(
            keychain: biometricKeychain,
            biometryAvailability: { .available }
        )
        lockService = AppLockService(defaults: defaults)

        coordinator = KeyshareWriteCoordinator()
        sut = KeyshareInstallReconciler(
            keychain: keychain,
            keyStore: keyStore,
            biometrics: biometrics,
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
        biometrics = nil
        biometricKeychain = nil
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

    // MARK: - Sealed shares with no key

    /// The whole matrix, because the interesting cell is the one nothing used to
    /// look at: a confirmed-absent wrapper over a store that still holds sealed
    /// shares. Every other cell has to keep behaving exactly as it did, or the
    /// census has changed something it was not supposed to.
    func testTheCensusOnlyChangesTheConfirmedAbsentSealedCell() {
        let wrappers: [(name: String, result: KeychainReadResult<Data>)] = [
            ("present", .present(wrappedBlob)),
            ("absent", .absent),
            ("unavailable", .unavailable(errSecInteractionNotAllowed))
        ]
        let censuses: [KeyshareInstallReconciler.SealedShareCensus] = [.sealed, .nothingSealed, .unknown]

        for wrapper in wrappers {
            for census in censuses {
                keychain.wrappedKeyshareDataKeyResult = wrapper.result
                // Restated per cell rather than left where the previous one put
                // it: the alignment writes the mode, so an assertion run against
                // whatever the last cell happened to leave behind is not the
                // cell it claims to be.
                lockService.mode = .passcode

                let outcome = sut.reconcile(isStoreEmpty: false, census: census)

                let expected: KeyshareInstallReconciler.Outcome
                if case .absent = wrapper.result, case .sealed = census {
                    expected = .sealedSharesWithoutTheirKey
                } else {
                    expected = .nothing
                }

                XCTAssertEqual(
                    outcome,
                    expected,
                    "census \(census) over a \(wrapper.name) wrapper"
                )
            }
        }
    }

    /// The cell above, stated as the state it actually is: the shares are
    /// ciphertext and the key is gone, so there is no mode repair to make. The
    /// mode is left alone deliberately — moving it would erase the only evidence
    /// left on the device that a passcode was ever set.
    func testSealedSharesWithNoWrappedKeyAreReportedAndTheModeIsLeftAlone() {
        lockService.mode = .passcode

        let outcome = sut.reconcile(isStoreEmpty: false, census: .sealed)

        XCTAssertEqual(outcome, .sealedSharesWithoutTheirKey)
        XCTAssertEqual(lockService.mode, .passcode, "there is nothing behind this gate to repair towards")
    }

    /// The reason the check keys on the census rather than on the lock mode.
    /// Anyone who has already hit this bug has `.deviceAuth` persisted — this
    /// very method wrote it on their first launch — so a condition gated on
    /// `.passcode` would miss exactly the installs that need reporting.
    func testSealedSharesAreReportedEvenWhenTheModeHasAlreadyBeenRepaired() {
        lockService.mode = .deviceAuth

        let outcome = sut.reconcile(isStoreEmpty: false, census: .sealed)

        XCTAssertEqual(outcome, .sealedSharesWithoutTheirKey)
    }

    /// An unreadable store must not raise it. The screen it drives is not
    /// dismissible, so raising one on a guess strands a user whose vaults are
    /// perfectly fine — and the condition does not depend on the mode, so the
    /// next launch that can read the store still finds it.
    func testAnUnreadableCensusReportsNothingAndStillRepairsTheMode() {
        lockService.mode = .passcode

        let outcome = sut.reconcile(isStoreEmpty: false, census: .unknown)

        XCTAssertEqual(outcome, .nothing)
        XCTAssertEqual(
            lockService.mode,
            .deviceAuth,
            "a gate no passcode can open is the lockout this branch exists to prevent; deferring is not the safe side"
        )
    }

    /// A store with nothing sealed in it is the interrupted-disable case the
    /// `.absent` branch has always repaired, and it must go on repairing it.
    func testAStoreWithNothingSealedStillFallsBackToDeviceAuth() {
        lockService.mode = .passcode

        let outcome = sut.reconcile(isStoreEmpty: false, census: .nothingSealed)

        XCTAssertEqual(outcome, .nothing)
        XCTAssertEqual(lockService.mode, .deviceAuth)
    }

    /// The census is taken from the store, and a store that answers "yes" has to
    /// reach the outcome. Asserted through `reconcile()` — the entry point the
    /// app actually calls — rather than through the seam, so a census that is
    /// computed but never passed down would fail here.
    @MainActor
    func testReconcileTakesTheCensusFromTheStore() {
        let sut = KeyshareInstallReconciler(
            keychain: keychain,
            keyStore: keyStore,
            biometrics: biometrics,
            lockService: lockService,
            coordinator: coordinator,
            sweeper: StubSweeper(answer: .success(true)),
            defaults: defaults
        )

        XCTAssertEqual(sut.reconcile(), .sealedSharesWithoutTheirKey)
    }

    @MainActor
    func testReconcileReportsNothingWhenTheStoreHoldsNoSealedShare() {
        let sut = KeyshareInstallReconciler(
            keychain: keychain,
            keyStore: keyStore,
            biometrics: biometrics,
            lockService: lockService,
            coordinator: coordinator,
            sweeper: StubSweeper(answer: .success(false)),
            defaults: defaults
        )

        XCTAssertEqual(sut.reconcile(), .nothing)
    }

    /// A census that throws is not an answer. `hasSealedShare()` refuses a
    /// context carrying unsaved work, and that refusal must not be read as
    /// either "sealed" or "nothing sealed".
    @MainActor
    func testACensusThatThrowsReportsNothing() {
        let sut = KeyshareInstallReconciler(
            keychain: keychain,
            keyStore: keyStore,
            biometrics: biometrics,
            lockService: lockService,
            coordinator: coordinator,
            sweeper: StubSweeper(answer: .failure(KeyshareSweeperError.busy)),
            defaults: defaults
        )

        XCTAssertEqual(sut.reconcile(), .nothing)
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

    // MARK: - The biometric copy

    /// A second copy of the same key, and it survives the uninstall too. Left
    /// behind it reports biometric unlock as already enabled and is bound to a
    /// wrapper this pass has just deleted, so it could only ever be refused.
    func testANewContainerClearsTheBiometricCopy() throws {
        try biometrics.enable(dataKey: try VaultCryptoEnvelope.randomKey(), boundTo: wrappedBlob)
        XCTAssertTrue(biometrics.isEnabled)

        sut.reconcile(isStoreEmpty: true)

        XCTAssertFalse(biometrics.isEnabled)
    }

    func testAStoreWithVaultsKeepsItsBiometricCopy() throws {
        try biometrics.enable(dataKey: try VaultCryptoEnvelope.randomKey(), boundTo: wrappedBlob)

        sut.reconcile(isStoreEmpty: false)

        XCTAssertTrue(biometrics.isEnabled)
    }

    func testAFailedBiometricClearIsRetriedOnTheNextLaunch() throws {
        try biometrics.enable(dataKey: try VaultCryptoEnvelope.randomKey(), boundTo: wrappedBlob)
        biometricKeychain.failsDeletion = true

        sut.reconcile(isStoreEmpty: true)

        XCTAssertTrue(biometrics.isEnabled)

        biometricKeychain.failsDeletion = false
        sut.reconcile(isStoreEmpty: true)

        XCTAssertFalse(biometrics.isEnabled)
    }

    /// The short-circuit that keeps a first-ever install from writing anything
    /// has to count the biometric copy too. A container carrying only that one
    /// would otherwise be judged to have inherited nothing, get marked as
    /// reconciled, and keep the leftover shortcut for good.
    func testAnInheritedBiometricCopyAloneStillTriggersTheClear() throws {
        try biometrics.enable(dataKey: try VaultCryptoEnvelope.randomKey(), boundTo: wrappedBlob)
        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
        XCTAssertEqual(keychain.getPasscodeAttemptState(), .absent)

        sut.reconcile(isStoreEmpty: true)

        XCTAssertFalse(biometrics.isEnabled)
    }
}

/// Answers the census and nothing else. Reconciliation never sweeps — it reads
/// the store and repairs Keychain-held state — so a sweep here fails loudly
/// rather than silently doing nothing.
private final class StubSweeper: KeyshareSweeping {

    private let answer: Result<Bool, Error>

    init(answer: Result<Bool, Error>) {
        self.answer = answer
    }

    @MainActor func sealAll() throws { XCTFail("reconciliation must not sweep") }
    @MainActor func unsealAll() throws { XCTFail("reconciliation must not sweep") }
    @MainActor func hasSealedShare() throws -> Bool { try answer.get() }
}

/// In-memory stand-in for the biometry-protected Keychain item — the real one
/// needs an entitlement and a device with biometrics enrolled.
private final class StubBiometricKeychain: BiometricKeychainProtecting {

    var failsDeletion = false

    private var items: [String: Data] = [:]

    /// An add, not an upsert, mirroring `SecItemAdd`.
    func store(_ data: Data, account: String) throws {
        guard items[account] == nil else { throw BiometricUnlockError.storageFailed }
        items[account] = data
    }

    func read(account: String, prompt _: String) throws -> Data {
        guard let data = items[account] else { throw BiometricUnlockError.notEnabled }
        return data
    }

    func delete(account: String) throws {
        guard !failsDeletion else { throw BiometricUnlockError.storageFailed }
        items[account] = nil
    }

    func exists(account: String) -> Bool {
        items[account] != nil
    }
}
