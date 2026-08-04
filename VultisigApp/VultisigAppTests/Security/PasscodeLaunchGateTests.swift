//
//  PasscodeLaunchGateTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

/// Pins one property: **the launch gate is chosen from a reconciled lock mode.**
///
/// The mode lives in `UserDefaults` and the wrapped data key lives in the
/// Keychain, so the two can disagree — `disablePasscode` changes the mode before
/// deleting the wrapper on purpose, so an interruption leaves a repairable state
/// rather than a gate with nothing behind it. `KeyshareInstallReconciler` is what
/// repairs it, and it also runs from the app's `onAppear`; nothing orders that
/// against the launch gate, so the gate could be chosen from a mode
/// reconciliation was about to change.
///
/// Both tests below assert on the *ordering* rather than on the eventual state:
/// reconciliation moves the mode, and what is checked is that the gate saw the
/// moved value. Neither passes if reconciliation runs after the mode is read, or
/// after the `mode == .passcode` guard.
@MainActor
final class PasscodeLaunchGateTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var lockService: AppLockService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "PasscodeLaunchGateTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        lockService = AppLockService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        lockService = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeViewModel(reconcile: @escaping @MainActor () -> Void) -> AppViewModel {
        AppViewModel(lockService: lockService, reconcileInstall: reconcile)
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
}
