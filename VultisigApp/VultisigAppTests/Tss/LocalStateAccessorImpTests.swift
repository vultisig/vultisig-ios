//
//  LocalStateAccessorImpTests.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest

// The type under test is handed to a Go binding that calls it from arbitrary
// threads, so these tests deliberately reach it from off the main actor. That is
// the behaviour being pinned, not an oversight, and the module is not built
// under Swift 6 checking — so the `Sendable` diagnostics it would raise here
// would be noise around the one place they are least informative.
@preconcurrency @testable import VultisigApp

/// The TSS binding calls `getLocalState` synchronously on whichever thread
/// entered it — in this app a `Task.detached(priority: .high)` worker, never the
/// main one. Reading a SwiftData `@Model` from there is undefined behaviour, so
/// the vault's shares are snapshotted on the MainActor at construction instead.
///
/// What these tests can and cannot prove is worth stating plainly: a data race
/// on a `@Model` is undefined behaviour, not a deterministic failure, so no test
/// can make the old code trap on demand. What they pin instead is the **seam** —
/// that the callback answers out of a value snapshot rather than out of the
/// model, and that the snapshot cannot outlive the protection state it was taken
/// under.
///
/// Two things keep them from passing for the wrong reason. Everything
/// constructs through `init(vault:)`, the one initializer production uses. And
/// the protection state is driven through the **real** `KeyshareKeySession` and
/// `KeyshareProtector` over a mock Keychain, rather than a hand-held state
/// closure — so "set a passcode", "lock" and "unlock" are the state transitions
/// production performs, not a test's idea of them.
@MainActor
final class LocalStateAccessorImpTests: XCTestCase {

    private let ecdsaPubKey = "02aaa"
    private let eddsaPubKey = "03bbb"
    private let ecdsaShare = "eyJrZXlzaGFyZSI6ImVjZHNhIn0="
    private let eddsaShare = #"{"PubKey":"03bbb","ShareID":{"value":"9"}}"#

    /// A real session and protector over a mock Keychain, wired the way
    /// production wires them: the protector reads its state from the session.
    private struct Environment {
        let keychain: MockKeychainService
        let session: KeyshareKeySession
        let protector: KeyshareProtector

        /// Models `setPasscode`: the wrapper becomes durable and the key is
        /// adopted, so the session reports `.unlocked`.
        @discardableResult
        func setPasscode() throws -> SymmetricKey {
            let key = try VaultCryptoEnvelope.randomKey()
            keychain.wrappedKeyshareDataKeyResult = .present(Data([0x01]))
            session.adopt(key)
            return key
        }

        /// Models `PasscodeService.lock()` — the only thing it does is forget
        /// the key, which bumps the session generation.
        func lock() {
            session.clear()
        }

        /// Models the unlock that follows: the key comes back without the
        /// generation moving again.
        func unlock(_ key: SymmetricKey) {
            session.adopt(key)
        }

        /// Models `disablePasscode`: every share is opened back to plaintext and
        /// the wrapper is deleted, so the session reports `.disabled`.
        func disablePasscode() {
            keychain.wrappedKeyshareDataKeyResult = .absent
            session.clear()
        }
    }

    private func makeEnvironment() -> Environment {
        let keychain = MockKeychainService()
        let session = KeyshareKeySession(store: DefaultKeyshareKeyStore(keychain: keychain))
        return Environment(
            keychain: keychain,
            session: session,
            protector: KeyshareProtector(state: { session.currentState() })
        )
    }

    private func makeVault(protector: KeyshareProtecting) throws -> Vault {
        let vault = Vault(name: "Test Vault")
        vault.pubKeyECDSA = ecdsaPubKey
        vault.pubKeyEdDSA = eddsaPubKey
        vault.keyshares = [
            try KeyShare.sealed(pubkey: ecdsaPubKey, keyshare: ecdsaShare, protector: protector),
            try KeyShare.sealed(pubkey: eddsaPubKey, keyshare: eddsaShare, protector: protector)
        ]
        return vault
    }

    private func makeEmptyVault() -> Vault {
        let vault = Vault(name: "Empty Vault")
        vault.pubKeyECDSA = ecdsaPubKey
        return vault
    }

    private func makeAccessor(vault: Vault, env: Environment) -> LocalStateAccessorImpl {
        LocalStateAccessorImpl(vault: vault, protector: env.protector, session: env.session)
    }

    // MARK: - The snapshot seam

    /// The regression this change exists for: after construction the callback
    /// must answer without reaching the `@Model` again. Emptying the vault is
    /// the observable stand-in for "the model is touched" — the previous
    /// implementation read `vault.keyshares` on every call and answered `""`.
    func testTheShareSnapshotIsNotReReadFromTheModel() throws {
        let env = makeEnvironment()
        let vault = try makeVault(protector: env.protector)
        let sut = makeAccessor(vault: vault, env: env)

        vault.keyshares = []

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), ecdsaShare)
        XCTAssertNil(error)
    }

    /// The same property from the thread the TSS binding actually uses.
    func testABackgroundCallbackAnswersFromTheSnapshot() throws {
        let env = makeEnvironment()
        let vault = try makeVault(protector: env.protector)
        let sut = makeAccessor(vault: vault, env: env)

        vault.keyshares = []

        let expected = ecdsaShare
        let pubKey = ecdsaPubKey
        let answered = expectation(description: "callback answered off the main thread")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread, "This test is only meaningful off the main thread")
            var error: NSError?
            XCTAssertEqual(sut.getLocalState(pubKey, error: &error), expected)
            XCTAssertNil(error)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
    }

    /// Reached concurrently during a ceremony, so the snapshot has to be
    /// readable from many threads at once without a lock.
    func testConcurrentReadsAllAnswerFromTheSnapshot() throws {
        let env = makeEnvironment()
        let vault = try makeVault(protector: env.protector)
        let sut = makeAccessor(vault: vault, env: env)
        let expected = ecdsaShare
        let pubKey = ecdsaPubKey

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            var error: NSError?
            XCTAssertEqual(sut.getLocalState(pubKey, error: &error), expected)
            XCTAssertNil(error)
        }
    }

    /// `Vault.keyshareValue(for:)` resolved duplicates with `first(where:)`;
    /// the snapshot has to resolve them the same way.
    func testADuplicatePublicKeyKeepsTheFirstShare() {
        let env = makeEnvironment()
        let vault = Vault(name: "Duplicate Vault")
        vault.keyshares = [
            KeyShare(pubkey: ecdsaPubKey, keyshare: ecdsaShare),
            KeyShare(pubkey: ecdsaPubKey, keyshare: "second-share-for-the-same-key")
        ]
        let sut = makeAccessor(vault: vault, env: env)

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), ecdsaShare)
        XCTAssertNil(error)
    }

    // MARK: - The read contract the TSS layer depends on

    func testAnUnknownPublicKeyAnswersEmptyWithNoError() throws {
        let env = makeEnvironment()
        let sut = makeAccessor(vault: try makeVault(protector: env.protector), env: env)

        var error: NSError?
        XCTAssertEqual(sut.getLocalState("not-a-key", error: &error), "")
        XCTAssertNil(error, "A vault with no share for this key is not an error")
    }

    func testANilPublicKeyAnswersEmptyWithNoError() throws {
        let env = makeEnvironment()
        let sut = makeAccessor(vault: try makeVault(protector: env.protector), env: env)

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(nil, error: &error), "")
        XCTAssertNil(error)
    }

    /// The snapshot holds shares **as stored**, so a sealed one is still opened
    /// per read rather than at construction. Keeping it that way is what stops
    /// the snapshot from parking plaintext key material in memory for the whole
    /// ceremony.
    func testASealedShareIsOpenedOnRead() throws {
        let env = makeEnvironment()
        try env.setPasscode()
        let vault = try makeVault(protector: env.protector)
        XCTAssertTrue(vault.keyshares[0].keyshare.hasPrefix(AesGcmKeyshareCipher.sealedPrefix))

        let sut = makeAccessor(vault: vault, env: env)

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), ecdsaShare)
        XCTAssertEqual(sut.getLocalState(eddsaPubKey, error: &error), eddsaShare)
        XCTAssertNil(error)
    }

    /// A locked app and a vault with no share for this key must stay
    /// distinguishable to the TSS layer — they need different handling and both
    /// used to look like `""`.
    func testALockedShareIsReportedThroughTheErrorPointer() throws {
        let env = makeEnvironment()
        try env.setPasscode()
        let vault = try makeVault(protector: env.protector)
        env.lock()

        let sut = makeAccessor(vault: vault, env: env)

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), "")
        XCTAssertEqual(error as? KeyshareProtectionError, .locked)
    }

    /// A `lock()` landing mid-ceremony has to still make a share that was sealed
    /// when the snapshot was taken unreadable. Opening at construction instead
    /// would defeat that.
    func testAShareSealedAtConstructionBecomesUnreadableOnceTheKeyIsGone() throws {
        let env = makeEnvironment()
        try env.setPasscode()
        let vault = try makeVault(protector: env.protector)

        let sut = makeAccessor(vault: vault, env: env)

        var beforeLock: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &beforeLock), ecdsaShare)
        XCTAssertNil(beforeLock)

        env.lock()

        var afterLock: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &afterLock), "")
        XCTAssertEqual(afterLock as? KeyshareProtectionError, .locked)
    }

    // MARK: - The snapshot cannot outlive the protection state it was taken under

    /// The window a snapshot opens that a per-call re-read did not, driven
    /// end-to-end through the real session: no passcode, ceremony starts, a
    /// passcode is set and the store is swept, then the app locks.
    ///
    /// Without the generation check `open` would hand the plaintext over
    /// forever, because a plaintext value passes through in **every** state —
    /// so a locked app would go on signing. That is the one direction in which
    /// snapshotting could be weaker than the read it replaced.
    func testAPlaintextSnapshotIsRefusedOnceAPasscodeIsSetAndTheAppLocks() throws {
        let env = makeEnvironment()
        let vault = try makeVault(protector: env.protector)
        XCTAssertEqual(vault.keyshares[0].keyshare, ecdsaShare, "No passcode: shares are stored in the clear")

        let sut = makeAccessor(vault: vault, env: env)

        var beforeTransition: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &beforeTransition), ecdsaShare)
        XCTAssertNil(beforeTransition)

        // setPasscode: the wrapper lands, the key is adopted, the sweep seals
        // the store behind the live ceremony.
        try env.setPasscode()
        vault.keyshares = [try KeyShare.sealed(pubkey: ecdsaPubKey, keyshare: ecdsaShare, protector: env.protector)]

        // Still unlocked, so signing continues — exactly what re-reading the
        // model and opening with the live key would have done.
        var whileUnlocked: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &whileUnlocked), ecdsaShare)
        XCTAssertNil(whileUnlocked)

        env.lock()

        var afterLock: NSError?
        XCTAssertEqual(
            sut.getLocalState(ecdsaPubKey, error: &afterLock),
            "",
            "A locked app must not keep handing a snapshotted plaintext share to the TSS layer"
        )
        XCTAssertEqual(afterLock as? KeyshareProtectionError, .locked)
    }

    /// The unlock that follows has to give the ceremony its share back, or the
    /// refusal above would turn a lock into a permanently broken keysign.
    func testAPlaintextSnapshotIsServedAgainOnceTheAppIsUnlocked() throws {
        let env = makeEnvironment()
        let vault = try makeVault(protector: env.protector)
        let sut = makeAccessor(vault: vault, env: env)

        let key = try env.setPasscode()
        env.lock()

        var afterLock: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &afterLock), "")
        XCTAssertEqual(afterLock as? KeyshareProtectionError, .locked)

        env.unlock(key)

        var afterUnlock: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &afterUnlock), ecdsaShare)
        XCTAssertNil(afterUnlock)
    }

    /// The guard that matters most: an install with **no passcode** is the
    /// permanent majority, and nothing about the refusal above may reach it. A
    /// generation bump with no wrapper in the Keychain still reads `.disabled`,
    /// so the share is served exactly as before.
    func testALockWithNoPasscodeSetStillServesThePlaintextSnapshot() throws {
        let env = makeEnvironment()
        let vault = try makeVault(protector: env.protector)
        let sut = makeAccessor(vault: vault, env: env)

        env.lock()

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), ecdsaShare)
        XCTAssertNil(error)
    }

    /// The other direction, unchanged and deliberately so: a disable unseals the
    /// store and destroys the key, and a ceremony holding a snapshot taken
    /// before it fails closed rather than signing. Worse availability than
    /// re-reading the model, never worse safety — and there is no way to see the
    /// unsealed value without reading the model this cannot touch.
    func testASnapshotTakenBeforeADisableFailsClosed() throws {
        let env = makeEnvironment()
        try env.setPasscode()
        let vault = try makeVault(protector: env.protector)

        let sut = makeAccessor(vault: vault, env: env)

        // The disable opens every stored share and then deletes the wrapper.
        vault.keyshares = [KeyShare(pubkey: ecdsaPubKey, keyshare: ecdsaShare)]
        env.disablePasscode()

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), "")
        XCTAssertEqual(error as? KeyshareProtectionError, .locked)
    }

    /// The ordering guarantee the refusal actually rests on, hammered
    /// concurrently: **a read that begins after `lock()` has returned is
    /// refused.**
    ///
    /// There is deliberately no mutual exclusion between a lock and a read.
    /// `PasscodeService.lock()` is `nonisolated` and synchronizes with nothing —
    /// a scene-phase lock must never block, least of all on an in-flight TSS
    /// round — so a lock that lands *concurrently* with a read is simply
    /// unordered against it, and no lease could change that: the signing layer
    /// is already holding the bytes it was handed earlier in the ceremony.
    ///
    /// What has to hold, and what this asserts, is the edge: once `lock()` has
    /// completed, nothing started afterwards hands the share over. The latch is
    /// set under its own lock *after* `lock()` returns, so a reader that
    /// observes it has a happens-before edge to `session.clear()` and must see
    /// the bumped generation.
    func testNoReadStartedAfterALockCompletesReturnsThePlaintextShare() throws {
        let env = makeEnvironment()
        let vault = try makeVault(protector: env.protector)
        XCTAssertEqual(vault.keyshares[0].keyshare, ecdsaShare, "The snapshot has to be plaintext for this to be the interesting case")

        let sut = makeAccessor(vault: vault, env: env)
        // A passcode arrives mid-ceremony, so a later lock has something to
        // refuse against.
        try env.setPasscode()

        let latch = LockLatch()
        let readsAfterLock = AtomicCounter()
        let plaintextAfterLock = AtomicCounter()
        let unexpectedAnswers = AtomicCounter()
        let pubKey = ecdsaPubKey
        let plaintext = ecdsaShare
        let deadline = Date().addingTimeInterval(10)

        DispatchQueue.global(qos: .userInitiated).async {
            env.lock()
            latch.mark()
        }

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            var observed = 0
            while observed < 25, Date() < deadline {
                // Sampled *before* the read starts, so "after the lock" means
                // the read began after `lock()` had already returned.
                let startedAfterLock = latch.isSet
                var error: NSError?
                let answer = sut.getLocalState(pubKey, error: &error)

                if answer != plaintext, !answer.isEmpty {
                    unexpectedAnswers.increment()
                }
                if startedAfterLock {
                    observed += 1
                    readsAfterLock.increment()
                    if answer == plaintext {
                        plaintextAfterLock.increment()
                    }
                }
            }
        }

        XCTAssertEqual(unexpectedAnswers.value, 0, "A read may only answer the share or nothing")
        XCTAssertGreaterThan(
            readsAfterLock.value,
            0,
            "Vacuous otherwise: the run has to actually contain reads that began after the lock returned"
        )
        XCTAssertEqual(
            plaintextAfterLock.value,
            0,
            "\(plaintextAfterLock.value) of \(readsAfterLock.value) reads begun after lock() returned still handed over the share"
        )
    }

    // MARK: - The write path is unchanged

    func testSaveLocalStateSealsThroughTheInjectedProtector() throws {
        let env = makeEnvironment()
        try env.setPasscode()
        let sut = makeAccessor(vault: makeEmptyVault(), env: env)

        try sut.saveLocalState(ecdsaPubKey, localState: ecdsaShare)

        XCTAssertEqual(sut.keyshares.count, 1)
        let stored = try XCTUnwrap(sut.keyshares.first)
        XCTAssertEqual(stored.pubkey, ecdsaPubKey)
        XCTAssertTrue(stored.keyshare.hasPrefix(AesGcmKeyshareCipher.sealedPrefix))
        XCTAssertEqual(try env.protector.open(stored.keyshare), ecdsaShare)
    }

    func testSaveLocalStateStoresPlaintextWhileProtectionIsDisabled() throws {
        let env = makeEnvironment()
        let sut = makeAccessor(vault: makeEmptyVault(), env: env)

        try sut.saveLocalState(ecdsaPubKey, localState: ecdsaShare)

        XCTAssertEqual(sut.keyshares.first?.keyshare, ecdsaShare)
    }

    func testSaveLocalStateRejectsMissingArguments() {
        let env = makeEnvironment()
        let sut = makeAccessor(vault: makeEmptyVault(), env: env)

        XCTAssertThrowsError(try sut.saveLocalState(nil, localState: ecdsaShare))
        XCTAssertThrowsError(try sut.saveLocalState(ecdsaPubKey, localState: nil))
        XCTAssertTrue(sut.keyshares.isEmpty)
    }
}

/// Set once, under its own lock, **after** `lock()` has returned — so a reader
/// that observes it set has a happens-before edge to `KeyshareKeySession.clear()`
/// and is obliged to see the bumped generation.
/// `@unchecked Sendable` is the truthful annotation: every access goes through
/// the `NSLock` below, which is what the readers and the locking thread rely on.
private final class LockLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// `DispatchQueue.concurrentPerform` bodies race on a plain `Int`.
private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
