//
//  KeygenVaultCommitTests.swift
//  VultisigAppTests
//
//  Pins the keygen-abort persistence fix: a secure keygen that is aborted at the
//  "Review Your Vaults" screen must NOT persist the vault, so its name stays
//  reusable. Only confirming ("Looks Good" -> `KeygenViewModel.commitVault`)
//  persists the vault and claims the name.
//

@testable import VultisigApp
import CryptoKit
import SwiftData
import XCTest

@MainActor
final class KeygenVaultCommitTests: XCTestCase {

    private var token: TestContextToken?

    private let firstShare = "eyJrZXlzaGFyZSI6ImRrbHMtb25lIn0="
    private let secondShare = "eyJrZXlzaGFyZSI6ImRrbHMtdHdvIn0="

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Every unique `String` attribute — `name`, `pubKeyECDSA`, `pubKeyEdDSA` —
    /// gets a value derived from `name`, so two differently named vaults are two
    /// rows. Sharing one, which `TestStore.makeVault` does with `pubKeyEdDSA`,
    /// makes SwiftData *upsert* rather than fail, and a fixture built that way
    /// silently collapses to a single row while every assertion still passes.
    /// (`publicKeyMLDSA44` is unique too but stays `nil`, which does not
    /// collapse — a unique index treats NULLs as distinct.)
    private func makeVault(name: String, shares: [String] = []) -> Vault {
        Vault(
            name: name,
            signers: ["iPhone-Local", "iPad-Peer"],
            pubKeyECDSA: "02\(name.lowercased())ecdsa",
            pubKeyEdDSA: "ed\(name.lowercased())eddsa",
            keyshares: shares.enumerated().map { index, value in
                KeyShare(pubkey: "\(name.lowercased())-share-\(index)", keyshare: value)
            },
            localPartyID: "iPhone-Local",
            hexChainCode: "00",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func persistedVaultCount() throws -> Int {
        try Storage.shared.modelContext.fetch(FetchDescriptor<Vault>()).count
    }

    private func persistedShares() throws -> [String] {
        try Storage.shared.modelContext
            .fetch(FetchDescriptor<Vault>())
            .flatMap(\.keyshares)
            .map(\.keyshare)
    }

    // MARK: - Tests

    /// Aborting the review screen never calls `commitVault`, so an in-memory vault
    /// that was generated but not confirmed leaves nothing in the store and keeps
    /// its name available.
    func test_abortedKeygen_doesNotPersistVault_andNameStaysReusable() throws {
        let name = "Treasury"

        // Fresh store: the name is available.
        XCTAssertTrue(VaultNameValidator().validateNonThrowable(value: name))

        // Keygen produced a vault in memory, but the user aborted at review:
        // `commitVault` is never called.
        _ = makeVault(name: name)

        XCTAssertEqual(try persistedVaultCount(), 0, "Aborted keygen must persist no vault")
        XCTAssertTrue(
            VaultNameValidator().validateNonThrowable(value: name),
            "Name must remain reusable after an aborted keygen"
        )
    }

    /// Confirming ("Looks Good") persists the vault and the name becomes taken,
    /// case-insensitively — matching `VaultNameValidator`.
    func test_confirmedKeygen_persistsVault_andClaimsNameCaseInsensitively() throws {
        let name = "Treasury"
        let vault = makeVault(name: name)

        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext)

        XCTAssertEqual(try persistedVaultCount(), 1, "Confirmed keygen must persist exactly one vault")

        // A new validator snapshots the now-persisted names.
        XCTAssertFalse(VaultNameValidator().validateNonThrowable(value: name))
        XCTAssertFalse(
            VaultNameValidator().validateNonThrowable(value: name.uppercased()),
            "Name uniqueness must be case-insensitive"
        )
    }

    /// Abort-then-retry with the same name succeeds: because the aborted attempt
    /// persisted nothing, committing the retried vault is accepted.
    func test_abortThenRetrySameName_succeeds() throws {
        let name = "Treasury"

        // First attempt aborted (never committed).
        _ = makeVault(name: name)
        XCTAssertTrue(VaultNameValidator().validateNonThrowable(value: name))

        // Retry with the same name, this time confirmed.
        let retry = makeVault(name: name)
        try KeygenViewModel.commitVault(retry, context: Storage.shared.modelContext)

        XCTAssertEqual(try persistedVaultCount(), 1)
        XCTAssertFalse(VaultNameValidator().validateNonThrowable(value: name))
    }

    // MARK: - Serialization against passcode transitions

    /// The commit is the moment freshly generated shares reach the store, so it
    /// takes a write lease of its own. A passcode transition rewriting every
    /// stored share has to stop it rather than let it insert underneath — the
    /// vault would otherwise land in whatever form the sweep had already passed.
    func testCommitVaultIsRefusedWhileAPasscodeTransitionIsHeld() throws {
        let lease = try KeyshareWriteCoordinator.shared.beginTransition()
        defer { KeyshareWriteCoordinator.shared.end(lease) }

        let vault = makeVault(name: "Treasury")

        XCTAssertThrowsError(try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext)) { error in
            XCTAssertEqual(error as? KeyshareWriteCoordinatorError, .busy)
        }
        XCTAssertEqual(try persistedVaultCount(), 0, "A refused commit must persist nothing")
    }

    func testCommitVaultSucceedsOnceTheTransitionEnds() throws {
        let lease = try KeyshareWriteCoordinator.shared.beginTransition()
        KeyshareWriteCoordinator.shared.end(lease)

        try KeygenViewModel.commitVault(makeVault(name: "Treasury"), context: Storage.shared.modelContext)

        XCTAssertEqual(try persistedVaultCount(), 1)
    }

    // MARK: - The shares have to still be readable

    /// The overwhelmingly common case: no passcode has ever been set, so the
    /// shares are plaintext and `open` is a passthrough. This has to stay a
    /// passthrough — a verification that rejected plaintext would break vault
    /// creation for nearly every install.
    func testCommitVaultPersistsPlaintextSharesWhenNoPasscodeIsSet() throws {
        let vault = makeVault(name: "Treasury", shares: [firstShare, secondShare])

        try KeygenViewModel.commitVault(
            vault,
            context: Storage.shared.modelContext,
            protector: KeyshareProtector(state: { .disabled })
        )

        XCTAssertEqual(try persistedVaultCount(), 1)
        XCTAssertEqual(try persistedShares().sorted(), [firstShare, secondShare].sorted())
    }

    /// A passcode is set and stayed set: the shares were sealed under the key
    /// still in hand, so they commit, byte for byte as keygen produced them.
    func testCommitVaultPersistsSharesSealedUnderTheCurrentKey() throws {
        // Captured once: a closure that minted a key per call would hand the
        // commit a different key from the one that sealed.
        let key = SymmetricKey(size: .bits256)
        let protector = KeyshareProtector(state: { .unlocked(key) })

        let sealed = try protector.seal(firstShare)
        XCTAssertTrue(protector.isSealed(sealed), "the fixture must actually be sealed")

        let vault = makeVault(name: "Treasury", shares: [sealed])

        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)

        XCTAssertEqual(try persistedVaultCount(), 1)
        XCTAssertEqual(try persistedShares(), [sealed], "the commit must not rewrite the share")
    }

    /// **The regression.** The episode lease is retained on the view model and
    /// released by `deinit`, so it lasts only as long as SwiftUI keeps a screen
    /// the user has navigated away from. Drop it early and the sequence below is
    /// reachable: the disable unseals every *stored* share and deletes the data
    /// key, these shares are in memory rather than in the store so the sweep
    /// never sees them, and committing afterwards writes a vault sealed under a
    /// key that no longer exists — complete-looking, permanently unsignable, and
    /// nothing ever revisits it.
    func testCommitVaultThrowsWhenThePasscodeWasDisabledDuringTheReview() throws {
        // Keygen brackets the whole vault-creation episode…
        let episode = try XCTUnwrap(KeyshareWriteCoordinator.shared.beginEpisode())

        let key = SymmetricKey(size: .bits256)
        var state: KeyshareProtectionState = .unlocked(key)
        let protector = KeyshareProtector(state: { state })

        let sealed = try protector.seal(firstShare)
        let vault = makeVault(name: "Treasury", shares: [sealed])

        // …but nothing guarantees the lease outlives the review screen.
        KeyshareWriteCoordinator.shared.end(episode)

        // With the episode gone the transition is allowed through: it sweeps the
        // store, deletes the wrapped key and clears the session.
        let transition = try KeyshareWriteCoordinator.shared.beginTransition()
        state = .disabled
        KeyshareWriteCoordinator.shared.end(transition)

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .unreadableKeyshare(pubkey: "treasury-share-0"))
        }
        XCTAssertEqual(try persistedVaultCount(), 0, "a vault nothing can open must not reach the store")
    }

    /// The refusal is only worth anything if it happens before the write, so on
    /// *this* path there is no vault, no coins, and nothing left dirty for an
    /// unrelated save to flush. (It says nothing about a failure inside
    /// `context.save()`, which is a separate, pre-existing path.)
    func testARefusedCommitLeavesTheStoreExactlyAsItWas() throws {
        let existing = makeVault(name: "Savings", shares: [secondShare])
        try KeygenViewModel.commitVault(
            existing,
            context: Storage.shared.modelContext,
            protector: KeyshareProtector(state: { .disabled })
        )
        let before = try persistedShares()

        let key = SymmetricKey(size: .bits256)
        var state: KeyshareProtectionState = .unlocked(key)
        let protector = KeyshareProtector(state: { state })
        let vault = makeVault(name: "Treasury", shares: [try protector.seal(firstShare)])
        state = .disabled

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)
        ) { error in
            // Named, so a transition lease leaked by another test cannot satisfy
            // this with a `.busy` that proves nothing about the new check.
            XCTAssertEqual(error as? KeygenCommitError, .unreadableKeyshare(pubkey: "treasury-share-0"))
        }

        XCTAssertEqual(try persistedVaultCount(), 1, "the refused vault must not reach the store")
        XCTAssertEqual(try persistedShares(), before, "the refusal must leave every stored share alone")
        XCTAssertFalse(
            Storage.shared.modelContext.hasChanges,
            "a refused commit must not leave a partial write in the context"
        )
    }

    /// A share sealed under a key that is present but wrong fails the same way.
    /// This is the interrupted-set shape — a wrapper exists, so the session is
    /// not `.disabled`, but it does not open these bytes.
    func testCommitVaultThrowsWhenTheKeyInHandDoesNotOpenTheShare() throws {
        let foreign = try AesGcmKeyshareCipher().seal(firstShare, with: SymmetricKey(size: .bits256))
        let vault = makeVault(name: "Treasury", shares: [foreign])
        let held = SymmetricKey(size: .bits256)

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: KeyshareProtector(state: { .unlocked(held) })
            )
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .unreadableKeyshare(pubkey: "treasury-share-0"))
        }
        XCTAssertEqual(try persistedVaultCount(), 0)
    }

    /// The `.locked` state is the one the check cannot see through: a wrapped
    /// key exists but is not in hand, so nothing here can tell a share sealed
    /// under it from a share sealed under a key that is gone. Fail closed —
    /// persisting a share nobody can prove is recoverable is the outcome this
    /// whole verification exists to prevent.
    func testCommitVaultThrowsWhileTheAppIsLocked() throws {
        let key = SymmetricKey(size: .bits256)
        var state: KeyshareProtectionState = .unlocked(key)
        let protector = KeyshareProtector(state: { state })
        let vault = makeVault(name: "Treasury", shares: [try protector.seal(firstShare)])

        state = .locked

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .unreadableKeyshare(pubkey: "treasury-share-0"))
        }
        XCTAssertEqual(try persistedVaultCount(), 0)
    }

    /// The loop has to name the share that failed, not the first one it looked
    /// at — a vault carries a share per curve, and key import adds one per chain.
    func testTheRefusalNamesTheShareThatCouldNotBeOpened() throws {
        let key = SymmetricKey(size: .bits256)
        let protector = KeyshareProtector(state: { .unlocked(key) })
        let foreign = try AesGcmKeyshareCipher().seal(secondShare, with: SymmetricKey(size: .bits256))
        let vault = makeVault(name: "Treasury", shares: [try protector.seal(firstShare), foreign])

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .unreadableKeyshare(pubkey: "treasury-share-1"))
        }
        XCTAssertEqual(try persistedVaultCount(), 0)
    }

    /// A sealed envelope wrapped around another one is not a share. Nothing in
    /// the app produces one — `seal` refuses to double-seal — but the two
    /// sibling commit paths (`KeyshareSweeper`, `ProtectedVaultImporter`) both
    /// refuse it, and unwrapping only the outer layer would write `vlt2:` to
    /// disk under the name of a key share.
    func testCommitVaultThrowsOnAnEnvelopeWrappedAroundAnotherEnvelope() throws {
        let key = SymmetricKey(size: .bits256)
        let cipher = AesGcmKeyshareCipher()
        let nested = try cipher.seal(try cipher.seal(firstShare, with: key), with: key)
        let vault = makeVault(name: "Treasury", shares: [nested])

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: KeyshareProtector(state: { .unlocked(key) })
            )
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .unreadableKeyshare(pubkey: "treasury-share-0"))
        }
        XCTAssertEqual(try persistedVaultCount(), 0)
    }

    /// The review screen renders `error.localizedDescription`. Without the
    /// `LocalizedError` conformance the user would be shown
    /// "(VultisigApp.KeygenCommitError error 0.)" for a dead vault.
    func testTheRefusalIsReportedInWordsRatherThanAsAnNSError() {
        let key = "keysharesUnreadableVaultNotSaved"
        let error = KeygenCommitError.unreadableKeyshare(pubkey: "treasury-share-0")

        // `.localized` hands back the key itself when the key is missing, so
        // comparing against `key.localized` alone would pass over an untranslated
        // build. This is what proves the copy actually exists.
        XCTAssertNotEqual(key.localized, key, "the string must be present in the bundled locale")

        XCTAssertEqual(error.errorDescription, key.localized)
        XCTAssertEqual(error.localizedDescription, key.localized)
        XCTAssertFalse(
            error.localizedDescription.contains("KeygenCommitError"),
            "the alert must not fall back to the raw NSError form"
        )
    }
}
