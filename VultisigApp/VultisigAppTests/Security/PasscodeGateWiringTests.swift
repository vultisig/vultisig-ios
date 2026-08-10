//
//  PasscodeGateWiringTests.swift
//  VultisigAppTests
//

import CryptoKit
import Security
import SwiftData
import XCTest
@testable import VultisigApp

/// The overlay half of *"nothing may leave a lock screen standing while
/// ``PasscodeService/isPasscodeGateRequired`` is false"*.
///
/// `PasscodeServiceTests` proves the service half — that a `disablePasscode`
/// completing across a background `lock()` returns with the predicate `false`.
/// That is worth nothing on its own: `AppViewModel.isPasscodeLocked` is what the
/// user is actually looking at, and it is a *cache* of the predicate taken when
/// the gate went up. Left cached, the completed disable leaves `.deviceAuth`, no
/// wrapper, and a screen whose only exit is an unlock that can answer nothing
/// but `notSet` — the force-quit trap.
///
/// So these drive a **real** `PasscodeService` over a mock Keychain and a real
/// sweeper over an in-memory store, and assert on the flag the overlay reads.
@MainActor
final class PasscodeGateWiringTests: XCTestCase {

    private var token: TestContextToken!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var keychain: MockKeychainService!
    private var keyStore: DefaultKeyshareKeyStore!
    private var session: KeyshareKeySession!
    private var lockService: AppLockService!
    private var coordinator: KeyshareWriteCoordinator!
    private var sweeper: KeyshareSweeper!
    private var biometricKeychain: InMemoryBiometricKeychain!
    private var biometrics: BiometricUnlockStore!
    private var service: PasscodeService!
    /// `AppViewModel`'s login flags are `@AppStorage`, so they read and write the
    /// standard defaults no matter which suite the lock service is on.
    private var standardDefaults: [String: Any?] = [:]
    private let borrowedDefaultsKeys = ["showCover", "isAuthenticationEnabled", "showOnboarding"]

    private let passcode = "123456"
    private let share = "eyJrZXlzaGFyZSI6ImRrbHMifQ=="

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "PasscodeGateWiringTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        token = try TestStore.installInMemoryContainer()
        context = token.container.mainContext

        keychain = MockKeychainService()
        let store = DefaultKeyshareKeyStore(keychain: keychain)
        let keySession = KeyshareKeySession(store: store)
        keyStore = store
        session = keySession
        lockService = AppLockService(defaults: defaults)
        coordinator = KeyshareWriteCoordinator()
        sweeper = KeyshareSweeper(
            protector: KeyshareProtector(state: { keySession.currentState() }),
            context: { [context] in context }
        )
        biometricKeychain = InMemoryBiometricKeychain()
        biometrics = BiometricUnlockStore(
            keychain: biometricKeychain,
            biometryAvailability: { .available }
        )
        service = makeService()

        for key in borrowedDefaultsKeys {
            standardDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in standardDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        standardDefaults = [:]
        defaults.removePersistentDomain(forName: suiteName)
        service = nil
        biometrics = nil
        biometricKeychain = nil
        sweeper = nil
        coordinator = nil
        lockService = nil
        session = nil
        keyStore = nil
        keychain = nil
        context = nil
        TestStore.restore(token)
        token = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// `biometrics` is injected rather than defaulted, and it is **not** optional
    /// polish: `BiometricUnlockStore.shared` reaches the device Keychain, so
    /// `disablePasscode` — which removes the shortcut before any share moves —
    /// throws `.storageFailed` out of a simulator against the default. The
    /// dependency is invisible from the layer below, where this file was written
    /// and passed.
    private func makeService(sweeper: KeyshareSweeping? = nil) -> PasscodeService {
        PasscodeService(
            keyStore: keyStore,
            session: session,
            lockService: lockService,
            limiter: PasscodeAttemptLimiter(keychain: keychain, uptime: { 1_000 }),
            coordinator: coordinator,
            sweeper: sweeper ?? self.sweeper,
            biometrics: biometrics
        )
    }

    private func makeViewModel() -> AppViewModel {
        AppViewModel(
            lockService: lockService,
            passcodeService: service,
            reconcileInstall: { }
        )
    }

    /// One vault, built here rather than through `TestStore.makeVault`, and the
    /// row count asserted: `makeVault` shares `pubKeyEdDSA` across calls, and a
    /// SwiftData `@Attribute(.unique)` collision *upserts* rather than failing,
    /// so a multi-vault fixture silently collapses into one row and every
    /// assertion over it passes vacuously.
    @discardableResult
    private func givenAVault(shares: [String]) throws -> Vault {
        let vault = Vault(
            name: "Vault one",
            signers: [],
            pubKeyECDSA: "ecdsa-one",
            pubKeyEdDSA: "eddsa-one",
            keyshares: shares.enumerated().map { KeyShare(pubkey: "one-\($0.offset)", keyshare: $0.element) },
            localPartyID: "party-one",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        context.insert(vault)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Vault>()), 1)
        return vault
    }

    private func storedShares() throws -> [String] {
        try context.fetch(FetchDescriptor<Vault>()).flatMap(\.keyshares).map(\.keyshare)
    }

    /// The app was away long enough that returning re-locks.
    ///
    /// It goes through `revokeAuth()` rather than seeding the timestamp
    /// directly, because a relock now requires the app to have actually left —
    /// an activation that followed no departure measures no time away, and a
    /// biometric sheet is exactly such an activation. Reaching past that and
    /// setting the clock by hand would test a sequence the app cannot produce.
    private func givenTheAppWasAwayLongEnoughToRelock(_ sut: AppViewModel) {
        lockService.autoLockInterval = .immediate
        sut.revokeAuth()
    }

    // MARK: - Raising

    func testAForegroundRelockRaisesTheGateWhileAPasscodeIsSet() async throws {
        try givenAVault(shares: [share])
        try await service.setPasscode(passcode)
        let sut = makeViewModel()
        givenTheAppWasAwayLongEnoughToRelock(sut)

        sut.enableAuth()

        XCTAssertTrue(sut.isPasscodeLocked)
        XCTAssertFalse(service.isSessionUnlocked, "raising the gate has to forget the key, not just draw a screen")
    }

    /// The mode alone would raise one. With the wrapper *confirmed* absent there
    /// is no passcode that could dismiss it, and forgetting the data key would
    /// discard the only copy of something no wrapper can hand back.
    func testAForegroundRelockRaisesNoGateWhenTheWrapperIsConfirmedAbsent() {
        lockService.mode = .passcode
        let sut = makeViewModel()
        givenTheAppWasAwayLongEnoughToRelock(sut)

        sut.enableAuth()

        XCTAssertFalse(sut.isPasscodeLocked)
    }

    /// Failing closed. An unreadable wrapper may well be there.
    func testAForegroundRelockRaisesTheGateWhenTheWrapperCannotBeRead() {
        lockService.mode = .passcode
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)
        let sut = makeViewModel()
        givenTheAppWasAwayLongEnoughToRelock(sut)

        sut.enableAuth()

        XCTAssertTrue(sut.isPasscodeLocked)
    }

    /// An install whose mode says `.passcode` over a wrapper that is provably
    /// gone gets **the other** gate, not none at all. Taking the passcode branch
    /// there would raise nothing and still return past this fallback, so a
    /// foreground that re-locks would leave the wallet on screen behind neither.
    func testAForegroundRelockWithNoPasscodeGateStillTakesTheDeviceAuthPath() {
        lockService.mode = .passcode
        let sut = makeViewModel()
        givenTheAppWasAwayLongEnoughToRelock(sut)

        sut.isAuthenticationEnabled = true
        sut.isAuthenticated = true
        sut.showSplashView = false

        sut.enableAuth()

        XCTAssertFalse(sut.isPasscodeLocked)
        XCTAssertFalse(sut.isAuthenticated, "the device-auth re-lock was skipped")
        XCTAssertTrue(sut.showSplashView, "the device-auth re-lock was skipped")
    }

    // MARK: - Lowering

    /// **The headline.** The service half is pinned by
    /// `PasscodeServiceTests.testADisableThatCompletesAcrossALockLeavesNoGateStanding`;
    /// this is the same sequence carried all the way to the flag the overlay is
    /// drawn from.
    ///
    /// The lock lands past the disable's abort cut-off — after the shares are
    /// back in the clear, where stopping would strand every one of them behind a
    /// passcode still being demanded — so the disable finishes. What it finishes
    /// into has to be somewhere the app can be got back into, and the foreground
    /// is where that becomes visible.
    func testADisableThatCompletesAcrossALockLeavesNoGateStandingInTheApp() async throws {
        try givenAVault(shares: [share])
        try await service.setPasscode(passcode)

        let sut = makeViewModel()
        givenTheAppWasAwayLongEnoughToRelock(sut)
        sut.enableAuth()
        XCTAssertTrue(sut.isPasscodeLocked, "the gate was legitimately up when the disable started")

        let locking = LockingKeyshareSweeper(wrapping: sweeper) { [session] in session?.clear() }
        try await makeService(sweeper: locking).disablePasscode(current: passcode)

        XCTAssertTrue(locking.didLock, "the fixture never landed its lock, so nothing was tested")
        XCTAssertEqual(try storedShares(), [share], "a completed disable puts the shares back in the clear")
        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
        XCTAssertFalse(service.isPasscodeGateRequired)

        sut.enableAuth()

        XCTAssertFalse(sut.isPasscodeLocked, "no gate may be left standing over a passcode that is gone")
    }

    /// The discriminator for the one above: the foreground lowers the gate
    /// because the predicate went false, not because it lowers gates.
    func testAForegroundLeavesTheGateUpWhileThePasscodeIsStillThere() async throws {
        try givenAVault(shares: [share])
        try await service.setPasscode(passcode)

        let sut = makeViewModel()
        sut.raisePasscodeGate()

        sut.enableAuth()

        XCTAssertTrue(sut.isPasscodeLocked)
    }

    /// And a Keychain that merely went quiet is not a passcode that went away.
    func testAForegroundLeavesTheGateUpWhenTheWrapperCannotBeRead() async throws {
        try givenAVault(shares: [share])
        try await service.setPasscode(passcode)

        let sut = makeViewModel()
        sut.raisePasscodeGate()
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        sut.enableAuth()

        XCTAssertTrue(sut.isPasscodeLocked)
    }

    /// The way out for someone already standing in front of the gate, without
    /// backgrounding the app and without a relaunch. `unlockApp` answers
    /// `notSet` — the *confirmed* absence, never a quiet Keychain — and repairs
    /// the mode on the spot; the screen reports the failed attempt, and this is
    /// what turns that report into the gate coming down.
    func testAnUnlockThatFindsThePasscodeGoneTakesTheGateDown() async throws {
        try givenAVault(shares: [share])
        try await service.setPasscode(passcode)

        let sut = makeViewModel()
        sut.raisePasscodeGate()

        // The state a disable completing behind a raised gate leaves, staged
        // directly so the assertion is about the overlay rather than about the
        // disable, which the test above already drives end to end.
        keychain.setWrappedKeyshareDataKey(nil)
        lockService.mode = .passcode

        do {
            try await service.unlockApp(with: passcode)
            XCTFail("Expected .notSet")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .notSet)
        }
        sut.lowerPasscodeGateIfNoLongerRequired()

        XCTAssertEqual(lockService.mode, .deviceAuth)
        XCTAssertFalse(sut.isPasscodeLocked)
    }

    /// The same hook, on the ordinary wrong-passcode attempt it also runs after.
    /// A gate that came down for a mistyped digit would be the whole feature
    /// undone.
    func testAFailedAttemptAgainstALivePasscodeLeavesTheGateUp() async throws {
        try givenAVault(shares: [share])
        try await service.setPasscode(passcode)

        let sut = makeViewModel()
        sut.raisePasscodeGate()

        do {
            try await service.unlockApp(with: "999999")
            XCTFail("Expected .wrongPasscode")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .wrongPasscode)
        }
        sut.lowerPasscodeGateIfNoLongerRequired()

        XCTAssertTrue(sut.isPasscodeLocked)
    }

    // MARK: - The privacy cover

    /// `.inactive` fires for a Control Centre pull and an incoming call as well
    /// as for a real backgrounding. Covering is right in all of them; starting
    /// the auto-lock clock is not, or a glance at Control Centre re-locks
    /// somebody who never left the app.
    func testCoveringForPrivacyDoesNotStartTheAutoLockClock() {
        let sut = makeViewModel()
        sut.showCover = false
        defaults.removeObject(forKey: "lastRecordedTime")

        sut.coverForPrivacy()

        XCTAssertTrue(sut.showCover)
        XCTAssertNil(
            defaults.string(forKey: "lastRecordedTime"),
            "covering is not leaving; the interval must not start here"
        )
    }

    /// The other half, so the pair is not just "cover does nothing": a real
    /// backgrounding still both covers and starts the clock.
    func testBackgroundingCoversAndStartsTheClock() {
        let sut = makeViewModel()
        sut.showCover = false
        defaults.removeObject(forKey: "lastRecordedTime")

        sut.revokeAuth()

        XCTAssertTrue(sut.showCover)
        XCTAssertNotNil(defaults.string(forKey: "lastRecordedTime"))
    }

    // MARK: - A foreground that lands mid-unlock

    /// The Face ID loop. A biometric prompt drives the app `.inactive` and then
    /// `.active`, so this runs while the user is still looking at the sheet —
    /// and at `immediate` the relock answer is unconditionally yes. Re-raising
    /// there would `lock()` the session the shortcut is opening and rebuild the
    /// screen underneath it, which starts the prompt again.
    func testAForegroundDoesNotRelockAGateThatIsAlreadyUp() async throws {
        try await service.setPasscode(passcode)
        lockService.autoLockInterval = .immediate

        let sut = makeViewModel()
        sut.raisePasscodeGate()
        let raisedGeneration = sut.passcodeGateGeneration
        // Something a re-raise would destroy: the shortcut's adopted key.
        _ = try await service.unlock(with: passcode)
        // Without a recorded backgrounding `shouldRelock` answers "first launch,
        // do nothing" and this passes without the guard ever being consulted.
        sut.revokeAuth()
        XCTAssertTrue(lockService.shouldRelock(), "precondition: the interval says relock")

        sut.enableAuth()

        XCTAssertTrue(sut.isPasscodeLocked, "the gate stays up; it was already up")
        XCTAssertEqual(
            sut.passcodeGateGeneration,
            raisedGeneration,
            "a re-raise would rebuild the lock screen and restart the biometric prompt"
        )
    }

    /// The half that must keep working: a foreground with no gate standing still
    /// raises one when the interval says so.
    func testAForegroundStillRaisesTheGateWhenNoneIsUp() async throws {
        try await service.setPasscode(passcode)
        lockService.autoLockInterval = .immediate

        let sut = makeViewModel()
        sut.revokeAuth()
        XCTAssertFalse(sut.isPasscodeLocked, "precondition: nothing is up")
        XCTAssertTrue(lockService.shouldRelock(), "precondition: the interval says relock")

        sut.enableAuth()

        XCTAssertTrue(sut.isPasscodeLocked)
    }

    /// Identity, not luck. A gate raised again while the previous screen is
    /// still fading out must not come back carrying the finished flag from the
    /// unlock that was dismissing it — that is the state where a correct
    /// passcode stops taking the screen down and only a force quit helps.
    func testEachRaiseGivesTheLockScreenAFreshIdentity() {
        let sut = makeViewModel()

        sut.raisePasscodeGate()
        let first = sut.passcodeGateGeneration
        sut.markPasscodeUnlocked()
        sut.raisePasscodeGate()

        XCTAssertNotEqual(sut.passcodeGateGeneration, first)
    }

    /// The Face ID loop, end to end. The lock screen raises the sheet itself,
    /// the sheet makes the app `.inactive` and then `.active`, and at
    /// `immediate` the old code answered "relock" to that — putting the gate
    /// back over the unlock that had just succeeded, rebuilding the lock screen
    /// and raising the sheet again.
    ///
    /// The timestamp is seeded on purpose: an earlier, real backgrounding did
    /// happen, so the interval alone still says yes. What says no is that *this*
    /// activation followed no departure.
    func testAnActivationThatFollowedNoBackgroundingDoesNotRelock() async throws {
        try await service.setPasscode(passcode)
        lockService.autoLockInterval = .immediate

        let sut = makeViewModel()
        sut.raisePasscodeGate()
        // The shortcut opening the app, then the screen coming down.
        _ = try await service.unlock(with: passcode)
        sut.markPasscodeUnlocked()
        XCTAssertFalse(sut.isPasscodeLocked, "precondition: the unlock succeeded")

        lockService.noteBackgrounded()
        XCTAssertTrue(lockService.shouldRelock(), "precondition: the interval on its own says relock")

        sut.enableAuth()

        XCTAssertFalse(
            sut.isPasscodeLocked,
            "a biometric sheet is not a backgrounding; relocking here restarts the prompt forever"
        )
    }

    /// And the departure that is real still relocks, at the same interval, so
    /// the guard above is not simply switching auto-lock off.
    func testAnActivationAfterARealBackgroundingStillRelocks() async throws {
        try await service.setPasscode(passcode)
        lockService.autoLockInterval = .immediate

        let sut = makeViewModel()
        sut.raisePasscodeGate()
        _ = try await service.unlock(with: passcode)
        sut.markPasscodeUnlocked()
        XCTAssertFalse(sut.isPasscodeLocked)

        sut.revokeAuth()
        sut.enableAuth()

        XCTAssertTrue(sut.isPasscodeLocked, "the app did leave, and the interval is immediate")
    }

    // MARK: - The lock screen's opening move

    /// The reported flash: with the shortcut enabled, the lock screen appeared
    /// and dismissed itself a moment later, because the keypad rendered while
    /// the automatic biometric attempt was still running. The keypad now waits
    /// until that question is settled.
    func testTheKeypadIsHiddenUntilTheBiometricAttemptResolves() async throws {
        let viewModel = PasscodeViewModel(service: service)

        XCTAssertFalse(
            viewModel.shouldPresentEntry,
            "a keypad on screen during the attempt is the flash this fixes"
        )

        await viewModel.beginUnlock(biometricReason: "reason")

        XCTAssertTrue(viewModel.shouldPresentEntry)
    }

    /// And it reveals on *every* path, including the one where the shortcut was
    /// offered and did not open the app. A missed reveal is a lock screen with
    /// no keypad, which no passcode can get past.
    func testTheKeypadIsRevealedAfterAnOfferedShortcutFailsToOpenTheApp() async throws {
        try await service.setPasscode(passcode)
        try await service.enableBiometricUnlock()
        // The copy is present, so the shortcut is offered — and the wrapper it
        // is bound to is about to stop being the one on disk, so the attempt
        // runs and refuses rather than being skipped.
        try await service.changePasscode(current: passcode, new: "654321")
        biometricKeychain.failsRead = true
        service.lock()

        let viewModel = PasscodeViewModel(service: service)
        await viewModel.beginUnlock(biometricReason: "reason")

        XCTAssertFalse(viewModel.didFinish, "precondition: the shortcut did not open the app")
        XCTAssertTrue(viewModel.shouldPresentEntry, "the passcode must still be reachable")
    }

    // MARK: - What the app is allowed to raise while the gate is up

    /// The gate has to apply to what the app *does*, not only to what it shows —
    /// the same rule `handleDeeplink` already follows. These pin the half of it
    /// that no lock screen can cover for itself: a sheet is presented in a layer
    /// an overlay does not reach, so a screen that raises one from its own load
    /// puts it *above* the lock. Three do, with no user action at all: the
    /// fast-vault password reminder, the monthly backup warning and the
    /// notifications intro.
    func testACheckThatComesDueWhileLockedDoesNotRun() {
        var sut = AppLockPresentationHold()

        XCTAssertFalse(sut.requested(whileLocked: true))
        XCTAssertTrue(sut.isHolding)
    }

    /// Held, not dropped. The reminder is owed either way; what the gate decides
    /// is when it may be asked for.
    func testAHeldCheckRunsWhenTheGateComesDown() {
        var sut = AppLockPresentationHold()
        _ = sut.requested(whileLocked: true)

        XCTAssertTrue(sut.lockChanged(isLocked: false))
        XCTAssertFalse(sut.isHolding)
    }

    /// A hold, not a queue. Every caller asks an idempotent "do I still owe this
    /// sheet?" question, so three asks behind the gate are one answer once it
    /// comes down — not three sheets.
    func testRepeatedRequestsBehindTheGateProduceOneRun() {
        var sut = AppLockPresentationHold()
        _ = sut.requested(whileLocked: true)
        _ = sut.requested(whileLocked: true)
        _ = sut.requested(whileLocked: true)

        XCTAssertTrue(sut.lockChanged(isLocked: false))
        XCTAssertFalse(sut.lockChanged(isLocked: false), "the hold was already spent")
    }

    /// The gate going *up* releases nothing. Without this the sequence
    /// lock → check → unlock → lock would raise the sheet on the second lock,
    /// which is the bug being fixed rather than the fix.
    func testTheGateGoingUpReleasesNothing() {
        var sut = AppLockPresentationHold()
        _ = sut.requested(whileLocked: true)

        XCTAssertFalse(sut.lockChanged(isLocked: true))
        XCTAssertTrue(sut.isHolding, "still owed, still held")
    }

    /// And an unlock with nothing held raises nothing, so the rule is not simply
    /// "present something whenever the gate comes down".
    func testAnUnlockWithNothingHeldRunsNothing() {
        var sut = AppLockPresentationHold()

        XCTAssertFalse(sut.lockChanged(isLocked: false))
    }

    /// The half that must keep working: with no gate up, a check runs where it
    /// always did and is never held.
    func testACheckThatComesDueWithNoGateUpRunsImmediately() {
        var sut = AppLockPresentationHold()

        XCTAssertTrue(sut.requested(whileLocked: false))
        XCTAssertFalse(sut.isHolding)
        XCTAssertFalse(sut.lockChanged(isLocked: false), "nothing was held, so nothing replays")
    }

    /// The race the hold has to survive. SwiftUI delivers the lock's `onChange`
    /// *after* the flag has already changed, so a request landing in that window
    /// sees an unlocked app and runs — and the drain still on its way would then
    /// run the same check a second time. Accepting a request has to discharge the
    /// hold, not only the drain.
    func testARequestThatOvertakesTheDrainRunsOnce() {
        var sut = AppLockPresentationHold()
        _ = sut.requested(whileLocked: true)

        XCTAssertTrue(sut.requested(whileLocked: false), "the flag is already down")

        XCTAssertFalse(sut.lockChanged(isLocked: false), "the drain has nothing left to run")
    }
}

/// Lands a lock at the far side of the disable's unseal — the point past which
/// the disable can no longer stop, because putting the shares back needs the
/// data key the lock has just discarded.
private final class LockingKeyshareSweeper: KeyshareSweeping {

    private let wrapped: KeyshareSweeping
    private let lock: () -> Void
    private(set) var didLock = false

    init(wrapping wrapped: KeyshareSweeping, lock: @escaping () -> Void) {
        self.wrapped = wrapped
        self.lock = lock
    }

    @MainActor func sealAll() throws { try wrapped.sealAll() }

    @MainActor func unsealAll() throws {
        try wrapped.unsealAll()
        didLock = true
        lock()
    }

    @MainActor func hasSealedShare() throws -> Bool { try wrapped.hasSealedShare() }
}

/// The biometric shortcut's store, in memory. An add rather than an upsert,
/// mirroring `SecItemAdd` — production cannot overwrite in place, and a double
/// that could would make the rebinding path look like something it is not.
private final class InMemoryBiometricKeychain: BiometricKeychainProtecting {

    private var stored: Data?
    var failsRead = false

    func store(_ data: Data, account _: String) throws {
        guard stored == nil else { throw BiometricUnlockError.storageFailed }
        stored = data
    }

    func read(account _: String, prompt _: String) throws -> Data {
        if failsRead { throw BiometricUnlockError.failed }
        guard let stored else { throw BiometricUnlockError.notEnabled }
        return stored
    }

    func delete(account _: String) throws { stored = nil }

    func exists(account _: String) -> Bool { stored != nil }
}
