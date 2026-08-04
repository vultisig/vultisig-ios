//
//  PasscodeServiceTests.swift
//  VultisigAppTests
//

import CryptoKit
import Security
import SwiftData
import XCTest
@testable import VultisigApp

/// Driven against a **real** `KeyshareSweeper` over an in-memory store rather
/// than a stub, because the thing worth pinning is not that the service calls a
/// collaborator — it is that a passcode set leaves no plaintext share behind and
/// a passcode removal leaves no sealed one.
@MainActor
final class PasscodeServiceTests: XCTestCase {

    private var token: TestContextToken!
    private var context: ModelContext!
    private var keychain: MockKeychainService!
    private var keyStore: DefaultKeyshareKeyStore!
    private var session: KeyshareKeySession!
    private var protector: KeyshareProtector!
    private var lockService: AppLockService!
    private var coordinator: KeyshareWriteCoordinator!
    private var sweeper: KeyshareSweeper!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: PasscodeService!

    /// Driven manually so backoff can be tested without sleeping, and so the
    /// clock-vs-uptime interaction is observable.
    private var uptime: TimeInterval = 1_000

    private let passcode = "12345"
    private let newPasscode = "98765"
    private let share = "eyJrZXlzaGFyZSI6ImRrbHMifQ=="
    private let otherShare = "eyJrZXlzaGFyZSI6ImRrbHMtdHdvIn0="

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "PasscodeServiceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        token = try TestStore.installInMemoryContainer()
        context = token.container.mainContext

        keychain = MockKeychainService()
        let store = DefaultKeyshareKeyStore(keychain: keychain)
        let keySession = KeyshareKeySession(store: store)
        keyStore = store
        session = keySession
        protector = KeyshareProtector(state: { keySession.currentState() })
        lockService = AppLockService(defaults: defaults)
        coordinator = KeyshareWriteCoordinator()
        sweeper = KeyshareSweeper(protector: protector, context: { [context] in context })

        sut = makeService()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        sweeper = nil
        coordinator = nil
        lockService = nil
        protector = nil
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

    private func makeService(
        keyStore: KeyshareKeyStoring? = nil,
        sweeper: KeyshareSweeping? = nil
    ) -> PasscodeService {
        PasscodeService(
            keyStore: keyStore ?? self.keyStore,
            session: session,
            lockService: lockService,
            limiter: PasscodeAttemptLimiter(keychain: keychain, uptime: { self.uptime }),
            coordinator: coordinator,
            sweeper: sweeper ?? self.sweeper
        )
    }

    // MARK: - Set

    func testSetPasscodeStoresTheWrappedKeyAndReportsItselfSet() async throws {
        try await sut.setPasscode(passcode)

        _ = try XCTUnwrapPresent(keyStore.loadWrappedDataKey())
        let isSet = await sut.isSet
        XCTAssertTrue(isSet)
    }

    func testSetPasscodeSwitchesTheLockMode() async throws {
        try await sut.setPasscode(passcode)

        XCTAssertEqual(lockService.mode, .passcode)
    }

    /// The invariant, in one assertion: with a passcode set, no stored share is
    /// unsealed. Opt-in encryption makes an accessor bypass *silent* — it writes
    /// plaintext and only breaks for passcode users — so this is the loud
    /// failure that would otherwise be missing.
    func testSetPasscodeSealsEveryStoredShare() async throws {
        try givenVaults([("vault-one", [share, otherShare]), ("vault-two", [share])])

        try await sut.setPasscode(passcode)

        let stored = try storedShares()
        XCTAssertEqual(stored.count, 3)
        for value in stored {
            XCTAssertTrue(protector.isSealed(value), "no stored share may stay plaintext behind a passcode")
        }
        XCTAssertEqual(try stored.map { try protector.open($0) }.sorted(), [share, share, otherShare].sorted())
    }

    /// Nothing to sweep is the common case — most people set a passcode on an
    /// empty or freshly restored device.
    func testSetPasscodeWithNoVaultsStoresTheWrapperAndNothingElse() async throws {
        try await sut.setPasscode(passcode)

        _ = try XCTUnwrapPresent(keyStore.loadWrappedDataKey())
        XCTAssertEqual(
            Set(keychain.writes),
            ["wrappedKeyshareDataKey", "passcodeAttemptState"],
            "only the wrapper and the attempt counter may be touched"
        )
    }

    func testSetPasscodeRefusesWhenOneIsAlreadySet() async throws {
        try await sut.setPasscode(passcode)

        do {
            try await sut.setPasscode(newPasscode)
            XCTFail("Expected .alreadySet")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .alreadySet)
        }
    }

    func testSetPasscodeRejectsAWrongLength() async throws {
        for candidate in ["1234", "123456", "abcde", ""] {
            do {
                try await sut.setPasscode(candidate)
                XCTFail("Expected .invalidLength for \(candidate)")
            } catch {
                XCTAssertEqual(error as? PasscodeError, .invalidLength)
            }
        }
    }

    /// Never mint over evidence. A sealed share with no readable wrapper means a
    /// key already exists somewhere; the fresh one minted here would open none
    /// of what it sealed, and storing its wrapper would make that permanent.
    func testSetPasscodeIsRefusedWhenAShareIsAlreadySealed() async throws {
        let foreign = try AesGcmKeyshareCipher().seal(share, with: SymmetricKey(size: .bits256))
        try givenVaults([("vault-one", [foreign])])
        keychain.resetWrites()

        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected .sealedSharesWithoutKey")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .sealedSharesWithoutKey)
        }

        XCTAssertEqual(keychain.writes, [], "no key may be minted over a store that is already sealed")
        XCTAssertEqual(try storedShares(), [foreign])
    }

    /// A completed disable leaves nothing sealed, so the guard above does not
    /// make the feature one-shot.
    func testAPasscodeCanBeSetAgainAfterBeingRemoved() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        try await sut.disablePasscode(current: passcode)

        try await sut.setPasscode(newPasscode)

        XCTAssertEqual(lockService.mode, .passcode)
        XCTAssertTrue(protector.isSealed(try XCTUnwrap(try storedShares().first)))
    }

    // MARK: - Set: interruption leaves a recoverable state

    /// The failure the ordering exists for. A sweep that cannot finish must
    /// leave the wrapper **and** the gate in place: deleting the wrapper would
    /// strand whatever had already been sealed, and dropping back to
    /// `.deviceAuth` would hide the passcode screen that the resume runs behind.
    func testAFailedSweepKeepsTheWrapperAndThePasscodeGate() async throws {
        let foreign = try AesGcmKeyshareCipher().seal(share, with: SymmetricKey(size: .bits256))
        try givenVaults([("vault-one", [share])])

        // Slipped in after the sealed-share guard has already run, so the sweep
        // is what fails rather than the precondition.
        let hooked = HookedKeyshareKeyStore(wrapping: keyStore) { [context] in
            let vault = try XCTUnwrap(try context?.fetch(FetchDescriptor<Vault>()).first)
            vault.keyshares = [KeyShare(pubkey: "vault-one-0", keyshare: foreign)]
            try context?.save()
        }

        do {
            try await makeService(keyStore: hooked).setPasscode(passcode)
            XCTFail("Expected the sweep to fail")
        } catch {
            XCTAssertEqual(error as? KeyshareSweeperError, .verificationFailed(pubkey: "vault-one-0"))
        }

        _ = try XCTUnwrapPresent(keyStore.loadWrappedDataKey())
        XCTAssertEqual(lockService.mode, .passcode, "the gate the resume runs behind must be up")
    }

    /// The other suspension point, and the one a late generation capture would
    /// miss: a lock landing while the store is scanned must win too, or the app
    /// finishes the set with the key live in memory behind a lock screen.
    func testALockDuringTheSealedShareScanWins() async throws {
        try givenVaults([("vault-one", [share])])
        let hooked = HookedKeyshareSweeper(wrapping: sweeper) { [session] in
            session?.clear()
        }

        do {
            try await makeService(sweeper: hooked).setPasscode(passcode)
            XCTFail("Expected .cancelledByLock")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .cancelledByLock)
        }

        XCTAssertEqual(try storedShares(), [share], "nothing may be sealed under a key the lock discarded")
        if case .unlocked = session.currentState() {
            XCTFail("the lock must not have been undone")
        }
    }

    /// A background lock landing mid-derivation wins, and the app is left in the
    /// pending-passcode state rather than silently unlocked: wrapper durable,
    /// gate up, key not adopted.
    func testALockDuringKeyDerivationWinsAndLeavesPendingPasscode() async throws {
        try givenVaults([("vault-one", [share])])
        let hooked = HookedKeyshareKeyStore(wrapping: keyStore) { [session] in
            session?.clear()
        }

        do {
            try await makeService(keyStore: hooked).setPasscode(passcode)
            XCTFail("Expected .cancelledByLock")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .cancelledByLock)
        }

        _ = try XCTUnwrapPresent(keyStore.loadWrappedDataKey())
        XCTAssertEqual(lockService.mode, .passcode)
        XCTAssertEqual(try storedShares(), [share], "the lock stands, so nothing was sealed under a forgotten key")
        if case .unlocked = session.currentState() {
            XCTFail("the lock must not have been undone")
        }
    }

    /// The wrapper has to be durable before a single share moves. A Keychain
    /// that accepts the write and stores nothing must therefore abort the set
    /// with the store untouched.
    func testAWrapperThatCannotBeStoredSealsNothing() async throws {
        try givenVaults([("vault-one", [share])])
        keychain.dropsWrappedKeyshareDataKeyWrites = true

        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected .persistenceFailed")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .persistenceFailed)
        }

        XCTAssertEqual(try storedShares(), [share])
        XCTAssertNotEqual(lockService.mode, .passcode)
    }

    // MARK: - Serialization

    /// Actors are reentrant at every `await`, so the lease — not the actor — is
    /// what keeps two transitions apart. The refusal has to land **before** any
    /// Keychain write, mode change or share rewrite, which is what the
    /// after-assertions pin: an implementation that took the lease late would
    /// still throw `.busy` and would still be wrong.
    func testATransitionIsRefusedWhileAnotherIsHeld() async throws {
        try givenVaults([("vault-one", [share])])
        keychain.resetWrites()
        let lease = try coordinator.beginTransition()
        defer { coordinator.end(lease) }

        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected .busy")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .busy)
        }

        XCTAssertEqual(keychain.writes, [])
        XCTAssertEqual(try storedShares(), [share])
        XCTAssertNotEqual(lockService.mode, .passcode)
    }

    /// The interval a per-write counter misses: TSS hands over a share long
    /// before `commitVault` stores it, and a passcode set landing in between
    /// would sweep a store that has never seen it.
    func testATransitionIsRefusedWhileAVaultCreationEpisodeIsOpen() async throws {
        try givenVaults([("vault-one", [share])])
        keychain.resetWrites()
        let episode = try XCTUnwrap(coordinator.beginEpisode())
        defer { coordinator.end(episode) }

        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected .busy")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .busy)
        }

        XCTAssertEqual(keychain.writes, [])
        XCTAssertEqual(try storedShares(), [share])
    }

    func testDisableIsRefusedWhileATransitionIsHeld() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        let sealed = try storedShares()
        keychain.resetWrites()
        let lease = try coordinator.beginTransition()
        defer { coordinator.end(lease) }

        do {
            try await sut.disablePasscode(current: passcode)
            XCTFail("Expected .busy")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .busy)
        }

        XCTAssertEqual(keychain.writes, [], "a refused disable must not touch the wrapper or the attempt counter")
        XCTAssertEqual(try storedShares(), sealed, "a refused disable must not open a single share")
        XCTAssertEqual(lockService.mode, .passcode)
    }

    func testChangeIsRefusedWhileATransitionIsHeld() async throws {
        try await sut.setPasscode(passcode)
        let wrappedBefore = keyStore.loadWrappedDataKey()
        keychain.resetWrites()
        let lease = try coordinator.beginTransition()
        defer { coordinator.end(lease) }

        do {
            try await sut.changePasscode(current: passcode, new: newPasscode)
            XCTFail("Expected .busy")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .busy)
        }

        XCTAssertEqual(keychain.writes, [])
        XCTAssertEqual(keyStore.loadWrappedDataKey(), wrappedBefore)
    }

    /// A refused transition must not leave a lease behind, or the next attempt
    /// fails for a reason that no longer exists.
    func testARefusedTransitionDoesNotStrandALease() async throws {
        let episode = try XCTUnwrap(coordinator.beginEpisode())
        _ = try? await sut.setPasscode(passcode)
        coordinator.end(episode)

        try await sut.setPasscode(passcode)

        XCTAssertEqual(lockService.mode, .passcode)
    }

    /// The other half: a transition that *acquired* the lease and then threw
    /// somewhere downstream has to release it on the way out.
    func testATransitionThatFailsDownstreamReleasesItsLease() async throws {
        keychain.dropsWrappedKeyshareDataKeyWrites = true
        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected the wrapper write to fail")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .persistenceFailed)
        }
        keychain.dropsWrappedKeyshareDataKeyWrites = false

        try await sut.setPasscode(passcode)

        XCTAssertEqual(lockService.mode, .passcode)
    }

    /// A store carrying somebody else's unsaved work cannot answer "is anything
    /// sealed?" truthfully — a pending edit or deletion hides the durable row —
    /// so the set is refused before a key is minted rather than after.
    func testASetIsRefusedOverADirtyStoreBeforeAnythingIsWritten() async throws {
        let vaults = try givenVaults([("vault-one", [share])])
        vaults[0].name = "renamed but not saved"
        XCTAssertTrue(context.hasChanges)
        keychain.resetWrites()

        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected .busy")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .busy)
        }

        XCTAssertEqual(keychain.writes, [], "no wrapper may be stored over a store that cannot be scanned")
        XCTAssertNotEqual(lockService.mode, .passcode)
    }

    // MARK: - Lock / unlock

    func testLockMakesSealedSharesUnreadable() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        let sealed = try XCTUnwrap(try storedShares().first)

        sut.lock()

        XCTAssertThrowsError(try protector.open(sealed)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
    }

    func testUnlockRestoresAccess() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        let sealed = try XCTUnwrap(try storedShares().first)
        sut.lock()

        try await sut.unlock(with: passcode)

        XCTAssertEqual(try protector.open(sealed), share)
    }

    func testUnlockWithTheWrongPasscodeLeavesTheAppLocked() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        let sealed = try XCTUnwrap(try storedShares().first)
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
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        let before = try storedShares()

        try await sut.changePasscode(current: passcode, new: newPasscode)

        XCTAssertEqual(try storedShares(), before, "No key share may be rewritten by a passcode change")
        XCTAssertEqual(try protector.open(try XCTUnwrap(before.first)), share)
    }

    func testChangedPasscodeUnlocksAndTheOldOneDoesNot() async throws {
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
        try await sut.setPasscode(passcode)

        do {
            try await sut.changePasscode(current: passcode, new: "1")
            XCTFail("Expected .invalidLength")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .invalidLength)
        }
    }

    // MARK: - Disable

    /// The inverse, asserted as such: the store comes back to the exact bytes it
    /// held before the passcode existed.
    func testDisableRestoresTheOriginalPlaintextAndRemovesTheWrappedKey() async throws {
        try givenVaults([("vault-one", [share, otherShare])])
        try await sut.setPasscode(passcode)

        try await sut.disablePasscode(current: passcode)

        XCTAssertEqual(try storedShares().sorted(), [share, otherShare].sorted())
        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
        let isSet = await sut.isSet
        XCTAssertFalse(isSet)
    }

    /// No unwrapped key is left behind. An earlier design stashed one beside the
    /// shares; a store left in that state reads as "no passcode" while its
    /// shares are still ciphertext.
    func testDisableLeavesNoKeyMaterialOfAnyFormBehind() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)

        try await sut.disablePasscode(current: passcode)

        XCTAssertAbsent(keyStore.loadDataKey(), "removing the passcode must not stash the key in the clear")
        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent)
        if case .disabled = session.currentState() {} else {
            XCTFail("with no key of either form the session must report .disabled")
        }
    }

    func testDisableReturnsTheLockToDeviceAuth() async throws {
        try await sut.setPasscode(passcode)

        try await sut.disablePasscode(current: passcode)

        XCTAssertEqual(lockService.mode, .deviceAuth)
    }

    func testDisableWithTheWrongPasscodeChangesNothing() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        let sealed = try storedShares()

        do {
            try await sut.disablePasscode(current: "00000")
            XCTFail("Expected .wrongPasscode")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .wrongPasscode)
        }

        XCTAssertEqual(try storedShares(), sealed)
        _ = try XCTUnwrapPresent(keyStore.loadWrappedDataKey())
    }

    /// One protocol, not a choice: restore `.passcode`, reseal transactionally,
    /// keep the wrapper, throw. The app is back to a working passcode and the
    /// user retries — the alternative leaves plaintext shares behind a gate.
    func testDisableResealsWhenTheWrappedKeyCannotBeDeleted() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        keychain.ignoresWrappedKeyshareDataKeyDeletion = true

        do {
            try await sut.disablePasscode(current: passcode)
            XCTFail("Expected the deletion failure to surface")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .deletionFailed)
        }

        let stored = try XCTUnwrap(try storedShares().first)
        XCTAssertTrue(protector.isSealed(stored), "the shares must go back behind the passcode that still exists")
        XCTAssertEqual(try protector.open(stored), share)
        _ = try XCTUnwrapPresent(keyStore.loadWrappedDataKey())
        XCTAssertEqual(lockService.mode, .passcode, "The passcode is still in force")
    }

    /// The rollback must not take "the deletion threw" to mean "the wrapper is
    /// still there". `deleteWrappedDataKey` verifies against a *confirmed*
    /// absence, so an unreadable read-back reports failure over a deletion that
    /// in fact happened — and resealing on that assumption would leave
    /// ciphertext whose only key is in memory until the next lock.
    func testDisableRestoresTheWrapperBeforeResealingWhenTheDeletionCannotBeConfirmed() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        keychain.wrappedKeyshareDataKeyBecomesUnreadableOnDeletion = true

        do {
            try await sut.disablePasscode(current: passcode)
            XCTFail("Expected the deletion failure to surface")
        } catch {
            XCTAssertEqual(error as? KeyshareKeyStoreError, .deletionFailed)
        }

        let restored = try XCTUnwrapPresent(keyStore.loadWrappedDataKey())
        XCTAssertFalse(restored.isEmpty)
        let stored = try XCTUnwrap(try storedShares().first)
        XCTAssertTrue(protector.isSealed(stored))
        XCTAssertEqual(try protector.open(stored), share)
        XCTAssertEqual(lockService.mode, .passcode)
    }

    /// And when the wrapper cannot be made durable again, nothing is resealed.
    /// Plaintext shares with no key of any form is the no-passcode resting
    /// state — the only outcome here that loses nothing.
    func testDisableLeavesSharesPlaintextWhenTheWrapperCannotBeRestored() async throws {
        try givenVaults([("vault-one", [share])])
        try await sut.setPasscode(passcode)
        keychain.wrappedKeyshareDataKeyBecomesUnreadableOnDeletion = true
        keychain.dropsWrappedKeyshareDataKeyWrites = true

        do {
            try await sut.disablePasscode(current: passcode)
            XCTFail("Expected .inconsistentState")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .inconsistentState)
        }

        XCTAssertEqual(try storedShares(), [share], "shares must stay readable when no wrapper can be proved")
        XCTAssertEqual(lockService.mode, .deviceAuth, "a gate with no wrapper behind it could never be opened")
        if case .unlocked = session.currentState() {
            XCTFail("a key with no durable wrapper must not stay cached — the next write would seal against it")
        }
    }

    /// A share that cannot be opened aborts the disable *before* the wrapper is
    /// touched. Reporting the removal as done would leave that value sealed with
    /// no passcode left to ask for.
    func testDisableAbortsWhenAShareCannotBeOpened() async throws {
        try await sut.setPasscode(passcode)
        let foreign = try AesGcmKeyshareCipher().seal(share, with: SymmetricKey(size: .bits256))
        try givenVaults([("vault-one", [foreign])])

        do {
            try await sut.disablePasscode(current: passcode)
            XCTFail("Expected the unseal to fail")
        } catch {
            XCTAssertEqual(error as? KeyshareSweeperError, .verificationFailed(pubkey: "vault-one-0"))
        }

        _ = try XCTUnwrapPresent(keyStore.loadWrappedDataKey())
        XCTAssertEqual(lockService.mode, .passcode)
        XCTAssertEqual(try storedShares(), [foreign])
    }

    // MARK: - Attempt limiting

    // MARK: - A malformed wrapped key is not a guess

    func testAMalformedWrappedKeyIsReportedAsStorageFailureAndNotCounted() async throws {
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
        try await sut.setPasscode(passcode)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0...PasscodeAttemptLimiter.freeAttempts {
            _ = try? await sut.unlock(with: "00000", now: start)
        }

        uptime += 3600
        try await sut.unlock(with: passcode, now: start.addingTimeInterval(3600))
    }

    func testASuccessfulUnlockClearsTheFailureCount() async throws {
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

    // MARK: - Helpers

    /// Every `@Attribute(.unique)` field is given a distinct value per vault.
    /// `TestStore.makeVault` leaves `pubKeyEdDSA` at a shared constant, and
    /// SwiftData answers a duplicate unique key with an *upsert* rather than an
    /// error — so a multi-vault fixture built that way silently collapses to one
    /// row and every multi-vault assertion passes vacuously.
    @discardableResult
    private func givenVaults(_ vaults: [(String, [String])]) throws -> [Vault] {
        let inserted = vaults.map { pubKey, shares in
            let vault = Vault(
                name: "Vault \(pubKey)",
                signers: [],
                pubKeyECDSA: "ecdsa-\(pubKey)",
                pubKeyEdDSA: "eddsa-\(pubKey)",
                keyshares: shares.enumerated().map { index, value in
                    KeyShare(pubkey: "\(pubKey)-\(index)", keyshare: value)
                },
                localPartyID: "party-\(pubKey)",
                hexChainCode: "hex",
                resharePrefix: nil,
                libType: .DKLS
            )
            context.insert(vault)
            return vault
        }
        try context.save()

        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Vault>()),
            vaults.count,
            "the fixture collapsed — a unique attribute is shared between vaults"
        )
        return inserted
    }

    private func storedShares() throws -> [String] {
        try context.fetch(FetchDescriptor<Vault>()).flatMap(\.keyshares).map(\.keyshare)
    }
}

// MARK: - Failing closed on an unreadable Keychain

extension PasscodeServiceTests {

    /// The lost-funds path this whole tri-state exercise exists to close. If an
    /// unreadable wrapper read as "no passcode", `setPasscode` would mint a
    /// fresh data key and store a wrapper over the top of the existing one —
    /// and the new key opens none of the shares the old one sealed.
    func testIsSetFailsClosedWhenTheWrapperCannotBeRead() async {
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        let isSet = await sut.isSet

        XCTAssertTrue(isSet, "An unreadable wrapper may well be there and must be treated as one")
    }

    func testSetPasscodeIsRefusedWhenTheWrapperCannotBeRead() async throws {
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)
        keychain.resetWrites()

        do {
            try await sut.setPasscode(passcode)
            XCTFail("Expected the set to be refused")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .alreadySet)
        }

        XCTAssertEqual(keychain.writes, [], "Nothing may be written while the Keychain cannot be read")
    }

    /// `notSet` is what sends the UI off to offer creating a passcode, over the
    /// top of a wrapper that may still exist.
    func testUnlockReportsStorageFailureRatherThanNotSetWhenTheWrapperCannotBeRead() async {
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)

        do {
            _ = try await sut.unlock(with: passcode)
            XCTFail("Expected the unlock to fail")
        } catch {
            XCTAssertEqual(error as? PasscodeError, .storageFailure)
        }
    }
}

// MARK: - The attempt limiter's own record

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

    /// The one deliberate exception to failing closed, pinned so it is a
    /// decision rather than an oversight. Answering an unreadable record with
    /// the maximum delay would never decay and could not be cleared by a correct
    /// passcode — clearing it needs a write the same Keychain would refuse — so
    /// it is a permanent lockout, and it buys nothing: deleting the item yields
    /// `.absent`, which is legitimately a fresh start anyway.
    func testAnUnreadableAttemptStateIsTreatedAsNoRecordRatherThanALockout() {
        keychain.passcodeAttemptStateResult = .unavailable(errSecInteractionNotAllowed)

        let limiter = PasscodeAttemptLimiter(keychain: keychain, uptime: { self.uptime })

        XCTAssertEqual(limiter.remainingLockout(now: Date()), 0)
    }

    /// A *corrupt* record is a different matter and still fails closed: it is
    /// present, so someone edited it, and resuming from zero would make editing
    /// the blob a way to buy free attempts.
    func testACorruptAttemptStateStillFailsClosed() {
        keychain.setPasscodeAttemptState(Data("not json".utf8))

        let limiter = PasscodeAttemptLimiter(keychain: keychain, uptime: { self.uptime })

        XCTAssertEqual(limiter.remainingLockout(now: Date()), PasscodeAttemptLimiter.maximumDelay)
    }
}

// MARK: - Test doubles

/// A sweeper that runs a hook inside the sealed-share scan — the *first*
/// suspension point of a set, and the one a generation captured too late would
/// leave unguarded.
private final class HookedKeyshareSweeper: KeyshareSweeping {

    private let wrapped: KeyshareSweeping
    private let duringScan: () throws -> Void

    init(wrapping wrapped: KeyshareSweeping, duringScan: @escaping () throws -> Void) {
        self.wrapped = wrapped
        self.duringScan = duringScan
    }

    @MainActor
    func hasSealedShare() throws -> Bool {
        try duringScan()
        return try wrapped.hasSealedShare()
    }

    @MainActor func sealAll() throws { try wrapped.sealAll() }
    @MainActor func unsealAll() throws { try wrapped.unsealAll() }
}

/// A key store that runs a hook inside `wrap`, which is the one long suspension
/// point in a transition. Everything a background lock or a concurrent write
/// could do mid-transition happens there, and driving it by hand is the only way
/// to make those races deterministic rather than timing-dependent.
private final class HookedKeyshareKeyStore: KeyshareKeyStoring {

    private let wrapped: KeyshareKeyStoring
    private let duringWrap: @MainActor () throws -> Void

    init(wrapping wrapped: KeyshareKeyStoring, duringWrap: @escaping @MainActor () throws -> Void) {
        self.wrapped = wrapped
        self.duringWrap = duringWrap
    }

    func generateDataKey() throws -> SymmetricKey { try wrapped.generateDataKey() }

    func loadDataKey() -> KeychainReadResult<SymmetricKey> { wrapped.loadDataKey() }
    func storeDataKey(_ key: SymmetricKey) throws { try wrapped.storeDataKey(key) }
    func deleteDataKey() throws { try wrapped.deleteDataKey() }

    func loadWrappedDataKey() -> KeychainReadResult<Data> { wrapped.loadWrappedDataKey() }
    func storeWrappedDataKey(_ blob: Data) throws { try wrapped.storeWrappedDataKey(blob) }
    func deleteWrappedDataKey() throws { try wrapped.deleteWrappedDataKey() }

    func wrap(_ key: SymmetricKey, passcode: String) async throws -> Data {
        let blob = try await wrapped.wrap(key, passcode: passcode)
        try await MainActor.run { try duringWrap() }
        return blob
    }

    func unwrap(_ blob: Data, passcode: String) async throws -> SymmetricKey {
        try await wrapped.unwrap(blob, passcode: passcode)
    }
}
