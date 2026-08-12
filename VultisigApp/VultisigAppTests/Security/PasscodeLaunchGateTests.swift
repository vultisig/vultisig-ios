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

    private var borrowedDidAskForAuthentication: Bool?

    override func setUpWithError() throws {
        try super.setUpWithError()
        borrowedDidAskForAuthentication = UserDefaults.standard.object(forKey: "didAskForAuthentication") as? Bool
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
        // `didAskForAuthentication` is `@AppStorage`, so the tests above wrote it
        // to the *standard* defaults rather than this suite's. Left there it
        // leaks into whatever runs next on the same simulator.
        if let borrowed = borrowedDidAskForAuthentication {
            UserDefaults.standard.set(borrowed, forKey: "didAskForAuthentication")
        } else {
            UserDefaults.standard.removeObject(forKey: "didAskForAuthentication")
        }
        borrowedDidAskForAuthentication = nil

        defaults.removePersistentDomain(forName: suiteName)
        passcodeService = nil
        keychain = nil
        lockService = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// - Parameters:
    ///   - outcome: what reconciliation reports back. Separate from the closure
    ///     below so a test can state the outcome without also having to model a
    ///     side effect, and vice versa.
    ///   - reconcile: reconciliation's side effect on the lock mode, run at the
    ///     moment the real one would run it.
    private func makeViewModel(
        outcome: KeyshareInstallReconciler.Outcome = .nothing,
        reconcile: @escaping @MainActor () -> Void = {}
    ) -> AppViewModel {
        AppViewModel(
            lockService: lockService,
            passcodeService: passcodeService,
            reconcileInstall: {
                reconcile()
                return outcome
            }
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

    // MARK: - Sealed shares with no key

    /// The launch this whole change exists for: the store came across in a
    /// restore and the Keychain wrapper did not, so the shares are ciphertext
    /// nothing on this device can read. The app must say so instead of opening.
    func testTheRecoveryScreenIsRaisedOverAnOrphanedInstall() {
        lockService.mode = .deviceAuth
        keychain.wrappedKeyshareDataKey = nil

        let sut = makeViewModel(outcome: .sealedSharesWithoutTheirKey)
        sut.restorePasscodeLockOnLaunch()

        XCTAssertTrue(sut.isKeyshareRecoveryRequired)
        XCTAssertFalse(sut.isPasscodeLocked, "there is no passcode behind this, and nothing to type")
    }

    /// A healthy install raises nothing, whichever gate it has. Without this the
    /// pair above would pass against a flag that is simply always true.
    func testTheRecoveryScreenIsNotRaisedOverAHealthyInstall() {
        lockService.mode = .passcode

        let sut = makeViewModel()
        sut.restorePasscodeLockOnLaunch()

        XCTAssertFalse(sut.isKeyshareRecoveryRequired)
        XCTAssertTrue(sut.isPasscodeLocked, "the ordinary passcode gate still goes up")
    }

    /// Reconciliation reports the orphaned state without touching the mode, so a
    /// stale `.passcode` can still be sitting there. The recovery screen wins:
    /// a lock screen whose only exit is an unlock that can answer nothing but
    /// `notSet` is the worse of the two to present.
    func testTheRecoveryScreenWinsOverAStalePasscodeMode() {
        lockService.mode = .passcode
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        let sut = makeViewModel(outcome: .sealedSharesWithoutTheirKey)
        sut.restorePasscodeLockOnLaunch()

        XCTAssertTrue(sut.isKeyshareRecoveryRequired)
        XCTAssertFalse(sut.isPasscodeLocked)
    }

    /// The screen points at the import flow, and the import flow is a screen in
    /// the app — which this is drawn over. So the route goes in **first** and
    /// the screen comes down after: lowering first uncovers the wallet while the
    /// push is still on its way, which is the silent open this state exists to
    /// prevent arriving by the one door left open.
    func testTheImportRouteIsPushedBeforeTheRecoveryScreenComesDown() {
        keychain.wrappedKeyshareDataKey = nil

        let sut = makeViewModel(outcome: .sealedSharesWithoutTheirKey)
        sut.restorePasscodeLockOnLaunch()

        sut.beginKeyshareRecoveryImport()
        XCTAssertTrue(sut.isKeyshareRecoveryRequired, "asking must not be enough to uncover the app")
        XCTAssertTrue(sut.isKeyshareRecoveryImportPending)

        var wasStillCoveredWhileRouting = false
        let claimed = sut.handOffToKeyshareRecoveryImport {
            wasStillCoveredWhileRouting = sut.isKeyshareRecoveryRequired
        }

        XCTAssertTrue(claimed)
        XCTAssertTrue(wasStillCoveredWhileRouting, "the push happens under the cover, not after it")
        XCTAssertFalse(sut.isKeyshareRecoveryRequired)
        XCTAssertFalse(sut.isKeyshareRecoveryImportPending)
    }

    /// Every mounted scene sees the request, and two of them routing is two
    /// import screens.
    func testOnlyOneSceneClaimsTheImportHandOff() {
        keychain.wrappedKeyshareDataKey = nil

        let sut = makeViewModel(outcome: .sealedSharesWithoutTheirKey)
        sut.restorePasscodeLockOnLaunch()
        sut.beginKeyshareRecoveryImport()

        var routes = 0
        XCTAssertTrue(sut.handOffToKeyshareRecoveryImport { routes += 1 })
        XCTAssertFalse(sut.handOffToKeyshareRecoveryImport { routes += 1 })

        XCTAssertEqual(routes, 1)
    }

    /// The cover predicate the rest of the app reads. A deeplink, a held sheet
    /// and a foreground push banner all have to treat this screen the way they
    /// treat the lock screen — otherwise they act, and are seen, behind it.
    func testTheRecoveryScreenCountsAsAnAppLockCover() {
        keychain.wrappedKeyshareDataKey = nil

        let sut = makeViewModel(outcome: .sealedSharesWithoutTheirKey)
        sut.restorePasscodeLockOnLaunch()

        XCTAssertFalse(sut.isPasscodeLocked, "precondition: it is not the gate that is up")
        XCTAssertTrue(sut.isCoveredByAppLock)

        sut.beginKeyshareRecoveryImport()
        sut.handOffToKeyshareRecoveryImport { }

        XCTAssertFalse(sut.isCoveredByAppLock)
    }

    /// And nothing else may start it. The hand-off lowers a screen the user is
    /// meant to be looking at, so a stray call would open the app over key
    /// shares it cannot read.
    func testTheImportHandOffDoesNothingWithoutARecoveryScreenUp() {
        let sut = makeViewModel()
        sut.restorePasscodeLockOnLaunch()

        sut.beginKeyshareRecoveryImport()

        XCTAssertFalse(sut.isKeyshareRecoveryImportPending)

        var routed = false
        XCTAssertFalse(sut.handOffToKeyshareRecoveryImport { routed = true })
        XCTAssertFalse(routed)
    }

    /// The same rule the passcode gate has: with the recovery screen up, the
    /// legacy device-auth path must not run. It is dismissed by no
    /// authentication of any kind, so a system biometric sheet in front of it
    /// is a prompt with nothing behind it.
    func testTheLegacyDeviceAuthIsNotRunWhileTheRecoveryScreenIsUp() {
        keychain.wrappedKeyshareDataKey = nil

        let sut = makeViewModel(outcome: .sealedSharesWithoutTheirKey)
        sut.didAskForAuthentication = false
        sut.restorePasscodeLockOnLaunch()
        XCTAssertTrue(sut.isKeyshareRecoveryRequired, "precondition: the recovery screen is up")

        sut.authenticateUser()

        XCTAssertTrue(sut.isKeyshareRecoveryRequired, "the recovery screen survives the splash's authentication")
        XCTAssertFalse(sut.showSplashView, "the splash comes down; the recovery screen is what covers the app")
        XCTAssertFalse(
            sut.didAskForAuthentication,
            "reaching the device-auth branch is what sets this, and it must not be reached"
        )
    }

    // MARK: - The splash, and the legacy gate behind it

    /// The bug this pair exists for: the splash used to authenticate and uncover
    /// the app before anything had decided whether to lock it.
    ///
    /// `authenticateUser()` is what the splash calls. With the launch gate up it
    /// must not reach the device-auth branch — a system biometric sheet in front
    /// of the lock screen is two gates for a user who picked one — and it must
    /// still take the splash down, because the lock screen already covers the app
    /// and a splash left underneath is where the launch would strand once the
    /// passcode is accepted.
    func testTheLegacyDeviceAuthIsNotRunWhileTheLaunchGateIsUp() {
        lockService.mode = .passcode

        let sut = makeViewModel { }
        // `@AppStorage`, so it is standard defaults rather than this suite's and
        // survives whatever ran before. Pinned rather than assumed.
        sut.didAskForAuthentication = false
        sut.restorePasscodeLockOnLaunch()
        XCTAssertTrue(sut.isPasscodeLocked, "precondition: the gate is up")

        sut.authenticateUser()

        XCTAssertTrue(sut.isPasscodeLocked, "the passcode gate survives the splash's authentication")
        XCTAssertFalse(sut.showSplashView, "the splash comes down; the lock screen is what covers the app")
        XCTAssertFalse(
            sut.didAskForAuthentication,
            "reaching the device-auth branch is what sets this, and it must not be reached"
        )
    }

    /// The other half: with no passcode gate, nothing here has changed. The
    /// legacy path still runs, so this is not a check that the guard is simply
    /// never taken.
    func testTheLegacyDeviceAuthStillRunsWithNoPasscodeGate() {
        lockService.mode = .deviceAuth
        keychain.wrappedKeyshareDataKey = nil

        let sut = makeViewModel { }
        sut.didAskForAuthentication = false
        sut.restorePasscodeLockOnLaunch()
        XCTAssertFalse(sut.isPasscodeLocked, "precondition: no gate")

        sut.authenticateUser()

        XCTAssertTrue(sut.didAskForAuthentication, "the legacy device-auth path was taken")
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
