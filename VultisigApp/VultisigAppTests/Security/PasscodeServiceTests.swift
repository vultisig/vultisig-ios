//
//  PasscodeServiceTests.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest
@testable import VultisigApp

final class PasscodeServiceTests: XCTestCase {

    private var keychain: MockKeychainService!
    private var keyStore: DefaultKeyshareKeyStore!
    private var session: KeyshareKeySession!
    private var protector: KeyshareProtector!
    private var lockService: AppLockService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: PasscodeService!

    /// Driven manually so backoff can be tested without sleeping, and so the
    /// clock-vs-uptime interaction is observable.
    private var uptime: TimeInterval = 1_000

    private let passcode = "12345"
    private let newPasscode = "98765"
    private let share = "eyJrZXlzaGFyZSI6ImRrbHMifQ=="

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "PasscodeServiceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        keychain = MockKeychainService()
        let store = DefaultKeyshareKeyStore(keychain: keychain)
        let keySession = KeyshareKeySession(store: store)
        keyStore = store
        session = keySession
        protector = KeyshareProtector(state: { keySession.currentState() })
        lockService = AppLockService(defaults: defaults)

        sut = PasscodeService(
            keyStore: store,
            session: keySession,
            lockService: lockService,
            limiter: PasscodeAttemptLimiter(keychain: keychain, uptime: { self.uptime }),
            biometrics: BiometricUnlockStore(keychain: InMemoryBiometricKeychain())
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        lockService = nil
        protector = nil
        session = nil
        keyStore = nil
        keychain = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Puts the app in the state the migration leaves it in: a data key exists
    /// in the clear and a share is sealed under it.
    @discardableResult
    private func givenMigratedState() throws -> String {
        let key = try keyStore.generateDataKey()
        try keyStore.storeDataKey(key)
        session.adopt(key)
        return try protector.seal(share)
    }

    // MARK: - Set

    func testSetPasscodeReplacesTheClearKeyWithAWrappedOne() async throws {
        try givenMigratedState()

        try await sut.setPasscode(passcode)

        XCTAssertNil(keyStore.loadDataKey(), "The clear copy must be gone")
        XCTAssertNotNil(keyStore.loadWrappedDataKey())
        let isSet = await sut.isSet
        XCTAssertTrue(isSet)
    }

    func testSetPasscodeSwitchesTheLockMode() async throws {
        try givenMigratedState()

        try await sut.setPasscode(passcode)

        XCTAssertEqual(lockService.mode, .passcode)
    }

    func testSetPasscodeKeepsSharesReadableInTheSameSession() async throws {
        let sealed = try givenMigratedState()

        try await sut.setPasscode(passcode)

        XCTAssertEqual(try protector.open(sealed), share)
    }

    func testSetPasscodeRefusesWhenNothingIsEncryptedYet() async {
        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected .noDataKey")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .noDataKey)
        }
    }

    func testSetPasscodeRefusesWhenOneIsAlreadySet() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)

        do {
            try await sut.setPasscode(newPasscode)
            XCTFail("Expected .alreadySet")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .alreadySet)
        }
    }

    func testSetPasscodeRejectsAWrongLength() async throws {
        try givenMigratedState()

        for candidate in ["1234", "123456", "abcde", ""] {
            do {
                try await sut.setPasscode(candidate)
                XCTFail("Expected .invalidLength for \(candidate)")
            } catch {
                XCTAssertEqual(error as? PasscodeError, .invalidLength)
            }
        }
    }

    // MARK: - Lock / unlock

    func testLockMakesSealedSharesUnreadable() async throws {
        let sealed = try givenMigratedState()
        try await sut.setPasscode(passcode)

        sut.lock()

        XCTAssertThrowsError(try protector.open(sealed)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
    }

    func testUnlockRestoresAccess() async throws {
        let sealed = try givenMigratedState()
        try await sut.setPasscode(passcode)
        sut.lock()

        try await sut.unlock(with: passcode)

        XCTAssertEqual(try protector.open(sealed), share)
    }

    func testUnlockWithTheWrongPasscodeLeavesTheAppLocked() async throws {
        let sealed = try givenMigratedState()
        try await sut.setPasscode(passcode)
        sut.lock()

        do {
            try await sut.unlock(with: "00000")
            XCTFail("Expected .wrongPasscode")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .wrongPasscode)
        }

        XCTAssertThrowsError(try protector.open(sealed))
    }

    func testUnlockWithoutAPasscodeSetThrows() async {
        do {
            try await sut.unlock(with: passcode)
            XCTFail("Expected .notSet")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .notSet)
        }
    }

    // MARK: - Change — the claim the whole design rests on

    /// Changing the passcode must rewrap 32 bytes and leave every key share
    /// byte-for-byte identical. The desktop client re-encrypts every share of
    /// every vault at this moment; if this assertion ever fails, that risk has
    /// been imported along with it.
    func testChangingThePasscodeLeavesKeyShareCiphertextByteIdentical() async throws {
        let sealed = try givenMigratedState()
        try await sut.setPasscode(passcode)
        let before = sealed

        try await sut.changePasscode(current: passcode, new: newPasscode)

        XCTAssertEqual(sealed, before, "No key share may be rewritten by a passcode change")
        XCTAssertEqual(try protector.open(sealed), share)
    }

    func testChangedPasscodeUnlocksAndTheOldOneDoesNot() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)
        try await sut.changePasscode(current: passcode, new: newPasscode)
        sut.lock()

        try await sut.unlock(with: newPasscode)

        sut.lock()
        do {
            try await sut.unlock(with: passcode)
            XCTFail("The old passcode must stop working")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .wrongPasscode)
        }
    }

    func testChangeWithTheWrongCurrentPasscodeChangesNothing() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)
        let wrappedBefore = keyStore.loadWrappedDataKey()

        do {
            try await sut.changePasscode(current: "00000", new: newPasscode)
            XCTFail("Expected .wrongPasscode")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .wrongPasscode)
        }

        XCTAssertEqual(keyStore.loadWrappedDataKey(), wrappedBefore)
    }

    func testChangeRejectsAnInvalidNewPasscode() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)

        do {
            try await sut.changePasscode(current: passcode, new: "1")
            XCTFail("Expected .invalidLength")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .invalidLength)
        }
    }

    // MARK: - Disable

    func testDisableRestoresTheClearKeyAndRemovesTheWrappedOne() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)

        try await sut.disablePasscode(current: passcode)

        XCTAssertNotNil(keyStore.loadDataKey())
        XCTAssertNil(keyStore.loadWrappedDataKey())
        let isSet = await sut.isSet
        XCTAssertFalse(isSet)
    }

    /// Turning the passcode off must not turn at-rest encryption off — the
    /// shares stay sealed, they are simply reachable without a passcode again.
    func testDisableLeavesSharesSealedAndReadable() async throws {
        let sealed = try givenMigratedState()
        try await sut.setPasscode(passcode)
        let before = sealed

        try await sut.disablePasscode(current: passcode)

        XCTAssertEqual(sealed, before, "No key share may be rewritten by disabling the passcode")
        XCTAssertTrue(sealed.hasPrefix(AesGcmKeyshareCipher.sealedPrefix))
        XCTAssertEqual(try protector.open(sealed), share)
    }

    func testDisableWithTheWrongPasscodeChangesNothing() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)

        do {
            try await sut.disablePasscode(current: "00000")
            XCTFail("Expected .wrongPasscode")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .wrongPasscode)
        }

        XCTAssertNil(keyStore.loadDataKey())
        XCTAssertNotNil(keyStore.loadWrappedDataKey())
    }

    /// If the wrapped copy cannot be removed, both copies would exist and the
    /// readable clear key would make the passcode meaningless. The clear copy is
    /// rolled back so the passcode keeps protecting something.
    func testDisableRollsBackWhenTheWrappedKeyCannotBeDeleted() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)
        keychain.ignoresWrappedKeyshareDataKeyDeletion = true

        do {
            try await sut.disablePasscode(current: passcode)
            XCTFail("Expected the deletion failure to surface")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .deletionFailed)
        }

        XCTAssertNil(keyStore.loadDataKey(), "The clear copy must have been rolled back")
        XCTAssertNotNil(keyStore.loadWrappedDataKey())
        XCTAssertEqual(lockService.mode, .passcode, "The passcode is still in force")
    }

    func testDisableReturnsTheLockToDeviceAuth() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)

        try await sut.disablePasscode(current: passcode)

        XCTAssertEqual(lockService.mode, .deviceAuth)
    }

    // MARK: - Attempt limiting

    // MARK: - Deletion must be verified

    /// If the clear copy survives, locking just reloads it from the Keychain and
    /// the passcode is decorative. Setting one must fail loudly instead.
    func testSetPasscodeFailsWhenTheClearKeyCannotBeDeleted() async throws {
        try givenMigratedState()
        keychain.ignoresKeyshareDataKeyDeletion = true

        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected .deletionFailed")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .deletionFailed)
        }

        XCTAssertNotEqual(lockService.mode, .passcode, "The mode must not switch on a failed deletion")
    }

    // MARK: - A malformed wrapped key is not a guess

    func testAMalformedWrappedKeyIsReportedAsStorageFailureAndNotCounted() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)
        keychain.setWrappedKeyshareDataKey(Data(repeating: 0x00, count: 64))

        for _ in 0..<10 {
            do {
                try await sut.unlock(with: passcode)
                XCTFail("Expected .storageFailure")
            } catch {
                XCTAssertEqual(error as? PasscodeError, .storageFailure)
            }
        }

        // Ten storage failures must not have accrued a lockout.
        XCTAssertEqual(PasscodeAttemptLimiter(keychain: keychain, uptime: { self.uptime }).remainingLockout(now: Date()), 0)
    }

    // MARK: - Clock manipulation

    /// Wall time alone is user-adjustable, so a backoff has to survive the clock
    /// being moved forward.
    func testMovingTheClockForwardDoesNotClearALockout() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0...PasscodeAttemptLimiter.freeAttempts {
            _ = try? await sut.unlock(with: "00000", now: start)
        }

        // A year later by the wall clock, but the device has not been up that
        // long — the monotonic reading is what counts.
        do {
            try await sut.unlock(with: passcode, now: start.addingTimeInterval(365 * 24 * 3600))
            XCTFail("Expected the lockout to survive a clock change")
        } catch {
            guard case .lockedOut? = error as? PasscodeError else {
                return XCTFail("Expected .lockedOut, got \(error)")
            }
        }
    }

    func testRepeatedFailuresEventuallyLockOut() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        for _ in 0..<PasscodeAttemptLimiter.freeAttempts {
            _ = try? await sut.unlock(with: "00000", now: start)
        }
        // The next failure crosses into the throttled range.
        _ = try? await sut.unlock(with: "00000", now: start)

        do {
            try await sut.unlock(with: passcode, now: start)
            XCTFail("Expected a lockout")
        } catch {
            guard case .lockedOut(let remaining)? = error as? PasscodeError else {
                return XCTFail("Expected .lockedOut, got \(error)")
            }
            XCTAssertGreaterThan(remaining, 0)
        }
    }

    /// Both clocks have to advance: wall time alone is the clock-manipulation
    /// bypass, and the limiter deliberately refuses to honour it.
    func testLockoutExpiresOnceTimeGenuinelyPasses() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0...PasscodeAttemptLimiter.freeAttempts {
            _ = try? await sut.unlock(with: "00000", now: start)
        }

        uptime += 3600
        try await sut.unlock(with: passcode, now: start.addingTimeInterval(3600))
    }

    func testASuccessfulUnlockClearsTheFailureCount() async throws {
        try givenMigratedState()
        try await sut.setPasscode(passcode)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0..<PasscodeAttemptLimiter.freeAttempts {
            _ = try? await sut.unlock(with: "00000", now: start)
        }

        try await sut.unlock(with: passcode, now: start)

        // Fresh budget: the free attempts are available again.
        for _ in 0..<PasscodeAttemptLimiter.freeAttempts {
            _ = try? await sut.unlock(with: "00000", now: start)
        }
        try await sut.unlock(with: passcode, now: start)
    }
}

extension PasscodeServiceTests {

    /// Failures with no recorded timestamp would slip past the lockout, so a
    /// decodable-but-inconsistent record counts as unreadable and fails closed.
    func testInconsistentAttemptStateFailsClosed() throws {
        let corrupt = #"{"failureCount":99}"#.data(using: .utf8)
        keychain.setPasscodeAttemptState(corrupt)

        let limiter = PasscodeAttemptLimiter(keychain: keychain, uptime: { self.uptime })

        XCTAssertEqual(limiter.remainingLockout(now: Date()), PasscodeAttemptLimiter.maximumDelay)
    }

    /// An absent record is a genuinely fresh start and must not be throttled.
    func testAbsentAttemptStateIsNotThrottled() {
        let limiter = PasscodeAttemptLimiter(keychain: keychain, uptime: { self.uptime })

        XCTAssertEqual(limiter.remainingLockout(now: Date()), 0)
    }

    /// A record whose failure count is within the free allowance needs no
    /// timestamps and stays valid.
    func testZeroFailureStateIsAccepted() throws {
        keychain.setPasscodeAttemptState(#"{"failureCount":0}"#.data(using: .utf8))

        let limiter = PasscodeAttemptLimiter(keychain: keychain, uptime: { self.uptime })

        XCTAssertEqual(limiter.remainingLockout(now: Date()), 0)
    }
}

/// The real biometric Keychain is unreachable from a test bundle (no
/// entitlement), so passcode tests drive an in-memory stand-in. Biometric
/// behaviour itself is covered by `BiometricUnlockStoreTests`.
private final class InMemoryBiometricKeychain: BiometricKeychainProtecting {

    private var stored: Data?

    func store(_ data: Data, account _: String) throws { stored = data }

    func read(account _: String, prompt _: String) throws -> Data {
        guard let stored else { throw BiometricUnlockError.notEnabled }
        return stored
    }

    func delete(account _: String) throws { stored = nil }

    func exists(account _: String) -> Bool { stored != nil }
}
