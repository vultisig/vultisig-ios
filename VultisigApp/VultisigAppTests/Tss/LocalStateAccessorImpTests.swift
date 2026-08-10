//
//  LocalStateAccessorImpTests.swift
//  VultisigAppTests
//

import XCTest

@testable import VultisigApp

/// The TSS binding calls `getLocalState` synchronously on whichever thread
/// entered it — in this app a `Task.detached(priority: .high)` worker, never the
/// main one. Reading a SwiftData `@Model` from there is undefined behaviour, so
/// the vault's shares are snapshotted on the MainActor at construction instead.
///
/// What these tests can and cannot prove is worth stating plainly: a data race
/// on a `@Model` is undefined behaviour, not a deterministic failure, so no test
/// can make the old code trap on demand. What they pin instead is the **seam** —
/// that the callback answers out of a value snapshot rather than out of the
/// model, which is checkable, fails against the previous implementation, and is
/// the only thing a future change could quietly undo.
final class LocalStateAccessorImpTests: XCTestCase {

    private let ecdsaPubKey = "02aaa"
    private let eddsaPubKey = "03bbb"
    private let ecdsaShare = "eyJrZXlzaGFyZSI6ImVjZHNhIn0="
    private let eddsaShare = #"{"PubKey":"03bbb","ShareID":{"value":"9"}}"#

    private func makeUnlockedProtector() throws -> KeyshareProtector {
        let key = try VaultCryptoEnvelope.randomKey()
        return KeyshareProtector(state: { .unlocked(key) })
    }

    @MainActor
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

    // MARK: - The snapshot seam

    /// The regression this change exists for: after construction the callback
    /// must answer without reaching the `@Model` again. Emptying the vault is
    /// the observable stand-in for "the model is touched" — the previous
    /// implementation read `vault.keyshares` on every call and answered `""`.
    @MainActor
    func testTheShareSnapshotIsNotReReadFromTheModel() throws {
        let protector = KeyshareProtector(state: { .disabled })
        let vault = try makeVault(protector: protector)
        let sut = LocalStateAccessorImpl(vault: vault, protector: protector)

        vault.keyshares = []

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), ecdsaShare)
        XCTAssertNil(error)
    }

    /// The same property from the thread the TSS binding actually uses.
    @MainActor
    func testABackgroundCallbackAnswersFromTheSnapshot() throws {
        let protector = KeyshareProtector(state: { .disabled })
        let vault = try makeVault(protector: protector)
        let sut = LocalStateAccessorImpl(vault: vault, protector: protector)

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
    func testConcurrentReadsAllAnswerFromTheSnapshot() {
        let protector = KeyshareProtector(state: { .disabled })
        let sut = LocalStateAccessorImpl(
            vaultShares: [ecdsaPubKey: ecdsaShare, eddsaPubKey: eddsaShare],
            protector: protector
        )
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
    @MainActor
    func testADuplicatePublicKeyKeepsTheFirstShare() {
        let protector = KeyshareProtector(state: { .disabled })
        let vault = Vault(name: "Duplicate Vault")
        vault.keyshares = [
            KeyShare(pubkey: ecdsaPubKey, keyshare: ecdsaShare),
            KeyShare(pubkey: ecdsaPubKey, keyshare: "second-share-for-the-same-key")
        ]
        let sut = LocalStateAccessorImpl(vault: vault, protector: protector)

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), ecdsaShare)
        XCTAssertNil(error)
    }

    // MARK: - The read contract the TSS layer depends on

    func testAnUnknownPublicKeyAnswersEmptyWithNoError() {
        let sut = LocalStateAccessorImpl(
            vaultShares: [ecdsaPubKey: ecdsaShare],
            protector: KeyshareProtector(state: { .disabled })
        )

        var error: NSError?
        XCTAssertEqual(sut.getLocalState("not-a-key", error: &error), "")
        XCTAssertNil(error, "A vault with no share for this key is not an error")
    }

    func testANilPublicKeyAnswersEmptyWithNoError() {
        let sut = LocalStateAccessorImpl(
            vaultShares: [ecdsaPubKey: ecdsaShare],
            protector: KeyshareProtector(state: { .disabled })
        )

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(nil, error: &error), "")
        XCTAssertNil(error)
    }

    /// The snapshot holds shares **as stored**, so a sealed one is still opened
    /// per read rather than at construction. Keeping it that way is what stops
    /// the snapshot from parking plaintext key material in memory for the whole
    /// ceremony.
    @MainActor
    func testASealedShareIsOpenedOnRead() throws {
        let protector = try makeUnlockedProtector()
        let vault = try makeVault(protector: protector)
        XCTAssertTrue(vault.keyshares[0].keyshare.hasPrefix(AesGcmKeyshareCipher.sealedPrefix))

        let sut = LocalStateAccessorImpl(vault: vault, protector: protector)

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), ecdsaShare)
        XCTAssertEqual(sut.getLocalState(eddsaPubKey, error: &error), eddsaShare)
        XCTAssertNil(error)
    }

    /// A locked app and a vault with no share for this key must stay
    /// distinguishable to the TSS layer — they need different handling and both
    /// used to look like `""`.
    @MainActor
    func testALockedShareIsReportedThroughTheErrorPointer() throws {
        let unlocked = try makeUnlockedProtector()
        let vault = try makeVault(protector: unlocked)
        let locked = KeyshareProtector(state: { .locked })

        let sut = LocalStateAccessorImpl(vault: vault, protector: locked)

        var error: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &error), "")
        XCTAssertEqual(error as? KeyshareProtectionError, .locked)
    }

    /// A locking `lock()` landing mid-ceremony has to still make a sealed share
    /// unreadable. Opening at construction instead would defeat that.
    @MainActor
    func testAShareSealedAtConstructionBecomesUnreadableOnceTheKeyIsGone() throws {
        let key = try VaultCryptoEnvelope.randomKey()
        var state: KeyshareProtectionState = .unlocked(key)
        let protector = KeyshareProtector(state: { state })
        let vault = try makeVault(protector: protector)

        let sut = LocalStateAccessorImpl(vault: vault, protector: protector)

        var beforeLock: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &beforeLock), ecdsaShare)
        XCTAssertNil(beforeLock)

        state = .locked

        var afterLock: NSError?
        XCTAssertEqual(sut.getLocalState(ecdsaPubKey, error: &afterLock), "")
        XCTAssertEqual(afterLock as? KeyshareProtectionError, .locked)
    }

    // MARK: - The write path is unchanged

    func testSaveLocalStateSealsThroughTheInjectedProtector() throws {
        let protector = try makeUnlockedProtector()
        let sut = LocalStateAccessorImpl(vaultShares: [:], protector: protector)

        try sut.saveLocalState(ecdsaPubKey, localState: ecdsaShare)

        XCTAssertEqual(sut.keyshares.count, 1)
        let stored = try XCTUnwrap(sut.keyshares.first)
        XCTAssertEqual(stored.pubkey, ecdsaPubKey)
        XCTAssertTrue(stored.keyshare.hasPrefix(AesGcmKeyshareCipher.sealedPrefix))
        XCTAssertEqual(try protector.open(stored.keyshare), ecdsaShare)
    }

    func testSaveLocalStateStoresPlaintextWhileProtectionIsDisabled() throws {
        let protector = KeyshareProtector(state: { .disabled })
        let sut = LocalStateAccessorImpl(vaultShares: [:], protector: protector)

        try sut.saveLocalState(ecdsaPubKey, localState: ecdsaShare)

        XCTAssertEqual(sut.keyshares.first?.keyshare, ecdsaShare)
    }

    func testSaveLocalStateRejectsMissingArguments() {
        let sut = LocalStateAccessorImpl(
            vaultShares: [:],
            protector: KeyshareProtector(state: { .disabled })
        )

        XCTAssertThrowsError(try sut.saveLocalState(nil, localState: ecdsaShare))
        XCTAssertThrowsError(try sut.saveLocalState(ecdsaPubKey, localState: nil))
        XCTAssertTrue(sut.keyshares.isEmpty)
    }
}
