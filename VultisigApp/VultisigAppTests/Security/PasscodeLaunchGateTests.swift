//
//  PasscodeLaunchGateTests.swift
//  VultisigAppTests
//

import Security
import XCTest
@testable import VultisigApp

/// Pins two properties of the launch gate: **it is chosen from a reconciled lock
/// mode**, and **it is chosen from the gate predicate rather than from the mode
/// alone**.
///
/// The mode lives in `UserDefaults` and the wrapped data key lives in the
/// Keychain, so the two can disagree — `disablePasscode` changes the mode before
/// deleting the wrapper on purpose, so an interruption leaves a repairable state
/// rather than a gate with nothing behind it. `KeyshareInstallReconciler` is what
/// repairs it, and it also runs from the app's `onAppear`; nothing orders that
/// against the launch gate, so the gate could be chosen from a mode
/// reconciliation was about to change.
///
/// The first three tests assert on the *ordering* rather than on the eventual
/// state: reconciliation moves the mode, and what is checked is that the gate saw
/// the moved value. None passes if reconciliation runs after the mode is read.
///
/// The last two assert on the predicate: a persisted `.passcode` over a
/// **confirmed-absent** wrapper raises nothing, because the only exit from that
/// screen is an unlock that can answer nothing but `notSet`; a wrapper that
/// merely could not be read still raises it, because the item may well be there.
@MainActor
final class PasscodeLaunchGateTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var lockService: AppLockService!
    private var keychain: MockKeychainService!
    private var passcodeService: PasscodeService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "PasscodeLaunchGateTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        lockService = AppLockService(defaults: defaults)

        keychain = MockKeychainService()
        // A wrapper for the mode to be about. The two tests where its absence is
        // the point stage that themselves.
        keychain.wrappedKeyshareDataKey = Data("wrapped-data-key".utf8)

        let keyStore = DefaultKeyshareKeyStore(keychain: keychain)
        passcodeService = PasscodeService(
            keyStore: keyStore,
            session: KeyshareKeySession(store: keyStore),
            lockService: lockService,
            limiter: PasscodeAttemptLimiter(keychain: keychain, uptime: { 1_000 }),
            coordinator: KeyshareWriteCoordinator(),
            sweeper: UnusedKeyshareSweeper()
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        passcodeService = nil
        keychain = nil
        lockService = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeViewModel(reconcile: @escaping @MainActor () -> Void) -> AppViewModel {
        AppViewModel(
            lockService: lockService,
            passcodeService: passcodeService,
            reconcileInstall: reconcile
        )
    }

    /// The interrupted-disable state: the mode was already switched to device
    /// auth, the wrapper deletion never landed, and reconciliation puts the gate
    /// back. Read before that, the gate is skipped and the app opens for the
    /// whole session over a wrapped key nobody was asked for.
    func testTheGateIsRaisedWhenReconciliationRestoresPasscodeMode() {
        lockService.mode = .deviceAuth

        let sut = makeViewModel { self.lockService.mode = .passcode }
        sut.restorePasscodeLockOnLaunch()

        XCTAssertTrue(sut.isPasscodeLocked)
    }

    /// The inverse, and the more dangerous direction to get wrong: a persisted
    /// passcode mode with no wrapper behind it is a gate `unlock` can never
    /// satisfy. Reconciliation takes it down, and the launch path has to see
    /// that rather than present a lock screen with nothing to verify against.
    func testTheGateIsNotRaisedWhenReconciliationClearsAStaleMode() {
        lockService.mode = .passcode

        let sut = makeViewModel { self.lockService.mode = .deviceAuth }
        sut.restorePasscodeLockOnLaunch()

        XCTAssertFalse(sut.isPasscodeLocked)
    }

    /// Reconciliation is unconditional. Gating it on the mode already being
    /// `.passcode` would skip exactly the case that needs repairing, since an
    /// interrupted disable leaves the mode at device auth.
    func testReconciliationRunsEvenWhenNoPasscodeModeIsConfigured() {
        lockService.mode = .off
        var didReconcile = false

        let sut = makeViewModel { didReconcile = true }
        sut.restorePasscodeLockOnLaunch()

        XCTAssertTrue(didReconcile)
        XCTAssertFalse(sut.isPasscodeLocked)
    }

    /// The same stale mode as above, but with nothing to repair it — a
    /// reconciliation that declined to act, or an install where the mode is
    /// simply ahead of the Keychain. The gate must not go up on the mode alone:
    /// with the wrapper *confirmed* gone there is no passcode that could ever
    /// dismiss it, and the only way out would be a force quit.
    func testTheGateIsNotRaisedWhenTheWrapperIsConfirmedAbsent() {
        lockService.mode = .passcode
        keychain.wrappedKeyshareDataKey = nil

        let sut = makeViewModel { }
        sut.restorePasscodeLockOnLaunch()

        XCTAssertFalse(sut.isPasscodeLocked)
        XCTAssertEqual(lockService.mode, .passcode, "the launch gate reads the mode, it does not write it")
    }

    /// And failing closed the other way. An unreadable Keychain is not evidence
    /// of anything, and a gate skipped over a momentary read failure is a
    /// passcode silently not asked for.
    func testTheGateIsRaisedWhenTheWrapperCannotBeRead() {
        lockService.mode = .passcode
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        let sut = makeViewModel { }
        sut.restorePasscodeLockOnLaunch()

        XCTAssertTrue(sut.isPasscodeLocked)
    }
}

/// The launch path locks and asks about the wrapper; it never sweeps. Failing
/// loudly is better than a silent no-op that would let a real sweep call hide.
///
/// Isolation sits on the methods rather than on the type, matching
/// `KeyshareSweeper`: an `actor` cannot be handed a main-actor-isolated value in
/// its own initializer.
private final class UnusedKeyshareSweeper: KeyshareSweeping {
    @MainActor func sealAll() throws { XCTFail("the launch gate must not sweep") }
    @MainActor func unsealAll() throws { XCTFail("the launch gate must not sweep") }
    @MainActor func hasSealedShare() throws -> Bool {
        XCTFail("the launch gate must not census the store")
        return false
    }
}
