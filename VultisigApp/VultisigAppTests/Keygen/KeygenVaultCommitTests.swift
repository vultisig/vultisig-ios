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
        // A successful commit hands out a token-discovery `Task` that can
        // outlive the test method and touch the models it resolved.
        TestStore.retain(try XCTUnwrap(token).container)
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
    ///
    /// Every share carries a `keyId`, which is not unique and does not collapse
    /// anything — it is here because the MLDSA share carries one in production
    /// and `DilithiumKeysign` builds its setup message from it, so a commit that
    /// dropped the field would leave a quantum vault unable to sign. Leaving it
    /// `nil` in every fixture would make that silent.
    private func makeVault(name: String, shares: [String] = []) -> Vault {
        Vault(
            name: name,
            signers: ["iPhone-Local", "iPad-Peer"],
            pubKeyECDSA: "02\(name.lowercased())ecdsa",
            pubKeyEdDSA: "ed\(name.lowercased())eddsa",
            keyshares: shares.enumerated().map { index, value in
                KeyShare(
                    pubkey: "\(name.lowercased())-share-\(index)",
                    keyshare: value,
                    keyId: "\(name.lowercased())-keyid-\(index)"
                )
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

    /// Read through a context that never saw the in-memory objects, so a
    /// pending insert cannot answer for a stored row. `Storage.shared`'s own
    /// context resolves pending inserts in every fetch, which is exactly the
    /// confusion the tests below are about.
    private func storedVaults() throws -> [Vault] {
        try ModelContext(try XCTUnwrap(token).container).fetch(FetchDescriptor<Vault>())
    }

    /// A store write that fails the way a real one does — the container
    /// unreachable, data protection unavailable, the disk full. SwiftData
    /// offers no way to make an in-memory `save()` fail on demand, which is why
    /// `commitVault` takes the write as a seam.
    private struct StoreUnavailable: Error {}

    private func failingSave(_: ModelContext) throws {
        throw StoreUnavailable()
    }

    /// Read through a context that never saw the in-memory objects, for the
    /// same reason as ``storedVaults()``.
    private func storedShares() throws -> [String] {
        try storedVaults().flatMap(\.keyshares).map(\.keyshare)
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

    // MARK: - The shares have to land on the side of the invariant the passcode is on

    /// The overwhelmingly common case: no passcode has ever been set, so the
    /// shares are plaintext and both halves of the normalization are
    /// passthroughs. This has to stay byte-identical — a commit that rewrote
    /// plaintext would change what nearly every install stores.
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
    /// still in hand, so they commit and stay sealed.
    ///
    /// Not byte-identical, deliberately. Normalizing opens and re-seals, and
    /// AES-GCM takes a fresh nonce per seal, so the stored ciphertext differs
    /// from the one keygen held. What has to hold is that it is still sealed and
    /// still opens to the same share — the invariant is about the *form* a value
    /// is in, not about its bytes.
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
        let stored = try XCTUnwrap(persistedShares().first)
        XCTAssertTrue(protector.isSealed(stored), "a passcode is set, so the stored share must be sealed")
        XCTAssertEqual(try protector.open(stored), firstShare, "and must open to exactly what keygen produced")
        XCTAssertNotEqual(
            stored,
            sealed,
            "an already-sealed share still goes through the seal, so the nonce — and the bytes — must differ"
        )
    }

    /// **The mirror regression.** The readability check the commit used to make
    /// closed only one direction: plaintext *is* readable, so a passcode **set**
    /// during the review sailed through it.
    ///
    /// Same broken lease as the disable case, run the other way. Keygen produced
    /// plaintext shares because no passcode existed at the time; the user then
    /// sets one, and the sweep seals every *stored* share while these sit in
    /// memory where it cannot reach them. Committing them as they are writes
    /// plaintext key material into a store with an active passcode — readable
    /// while the app is locked, and left that way indefinitely, since the sweep
    /// that would have sealed it has already run.
    ///
    /// Unlike the disable case this is repairable, so it is repaired rather than
    /// refused: refusing would destroy a finished keygen — unrepeatable without
    /// every co-signer back on the same screen — to prevent an exposure that
    /// this very write is about to end.
    func testCommitVaultSealsPlaintextSharesWhenThePasscodeWasSetDuringTheReview() throws {
        // Keygen brackets the whole vault-creation episode, with no passcode in
        // force, so the shares it produces are plaintext…
        let episode = try XCTUnwrap(KeyshareWriteCoordinator.shared.beginEpisode())

        var state: KeyshareProtectionState = .disabled
        let protector = KeyshareProtector(state: { state })
        let vault = makeVault(name: "Treasury", shares: [firstShare, secondShare])

        // …but nothing guarantees the lease outlives the review screen.
        KeyshareWriteCoordinator.shared.end(episode)

        // With the episode gone the transition is allowed through: it mints a
        // data key and seals every share it can find in the store. These are not
        // in the store.
        let key = SymmetricKey(size: .bits256)
        let transition = try KeyshareWriteCoordinator.shared.beginTransition()
        state = .unlocked(key)
        KeyshareWriteCoordinator.shared.end(transition)

        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)

        XCTAssertEqual(try persistedVaultCount(), 1)
        let stored = try persistedShares()
        XCTAssertEqual(stored.count, 2)
        for share in stored {
            XCTAssertTrue(
                protector.isSealed(share),
                "a passcode is set, so no share may reach the store in the clear"
            )
        }
        XCTAssertEqual(
            try stored.map { try protector.open($0) }.sorted(),
            [firstShare, secondShare].sorted(),
            "sealing must be reversible — the stored shares have to open back to what keygen produced"
        )
    }

    /// Normalizing rewrites the vault the caller handed over, not a copy of it,
    /// so the review screen is not left holding plaintext shares after the store
    /// has been told they are sealed. And it carries the rest of the share
    /// across — a `KeyShare` is rebuilt, not mutated, so a dropped field would
    /// be silent.
    func testCommitVaultRewritesTheVaultItWasHandedRatherThanACopy() throws {
        let key = SymmetricKey(size: .bits256)
        let protector = KeyshareProtector(state: { .unlocked(key) })
        let vault = makeVault(name: "Treasury", shares: [firstShare])

        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)

        let share = try XCTUnwrap(vault.keyshares.first)
        XCTAssertTrue(protector.isSealed(share.keyshare), "the vault the caller still holds must not keep plaintext")
        XCTAssertEqual(share.pubkey, "treasury-share-0", "normalizing must not lose the pubkey")
        XCTAssertEqual(
            share.keyId,
            "treasury-keyid-0",
            "nor the key identifier — an MLDSA share cannot be signed with without it"
        )
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

    /// Locked with *plaintext* shares in hand is the other half of the same
    /// refusal, and the one normalizing introduces: the shares read back
    /// perfectly — plaintext always does — but there is no key to seal them
    /// with, so the only two options are to store key material in the clear
    /// behind an active passcode or to refuse. It refuses, under its own error:
    /// nothing is lost here, and the next unlock stores the vault correctly.
    func testCommitVaultThrowsWhenPlaintextSharesCannotBeSealedWhileLocked() throws {
        let vault = makeVault(name: "Treasury", shares: [firstShare])

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: KeyshareProtector(state: { .locked })
            )
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .unsealableKeyshare(pubkey: "treasury-share-0"))
        }
        XCTAssertEqual(try persistedVaultCount(), 0, "plaintext must never reach a store with a passcode set")
        XCTAssertFalse(
            Storage.shared.modelContext.hasChanges,
            "a refused commit must not leave a partial write in the context"
        )
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

    // MARK: - All of it or none of it, when the save throws

    /// **The regression.** A throwing `save()` writes nothing to the store, so
    /// nothing is half-written *there* — but the vault and its coins stay
    /// registered in a context the whole app shares, and SwiftData resolves a
    /// pending insert in every fetch. The review screen said the vault could not
    /// be saved and the app went on answering that it existed.
    func testAFailedSaveLeavesNothingFetchableAndNothingPending() throws {
        let vault = makeVault(name: "Treasury", shares: [firstShare])

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: KeyshareProtector(state: { .disabled }),
                save: failingSave
            )
        ) { error in
            XCTAssertTrue(error is StoreUnavailable, "the store's own failure has to reach the caller unchanged")
        }

        XCTAssertEqual(try persistedVaultCount(), 0, "a vault whose save threw must not answer a fetch")
        XCTAssertFalse(
            Storage.shared.modelContext.hasChanges,
            "and must not be left pending for something else to flush"
        )
    }

    /// The half that makes it durable. Nothing about the failure stops the next
    /// unrelated `save()` anywhere in the app — or the main context's autosave —
    /// from writing the pending insert for real, minutes later and *outside* the
    /// write lease this commit holds.
    func testAFailedSaveDoesNotBecomeDurableOnTheNextUnrelatedSave() throws {
        let vault = makeVault(name: "Treasury", shares: [firstShare])

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: KeyshareProtector(state: { .disabled }),
                save: failingSave
            )
        )

        // Something else in the app saves the shared context.
        try Storage.shared.modelContext.save()

        XCTAssertEqual(try storedVaults().count, 0, "a refused vault must not reach disk on somebody else's save")
    }

    /// The vault is handed back in the form it arrived in, not the form the
    /// commit computed. Keygen produced plaintext shares, the user set a
    /// passcode during the review, so the commit sealed them — and then the save
    /// threw. Left sealed, disabling the passcode before retrying would make
    /// them unopenable under every state and the vault uncommittable for good.
    func testAFailedSaveGivesTheSharesBackInTheFormTheyArrivedIn() throws {
        var state: KeyshareProtectionState = .disabled
        let protector = KeyshareProtector(state: { state })
        let vault = makeVault(name: "Treasury", shares: [firstShare])

        // A passcode set while the review screen was up.
        state = .unlocked(SymmetricKey(size: .bits256))

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: protector,
                save: failingSave
            )
        )

        XCTAssertEqual(
            vault.keyshares.map(\.keyshare),
            [firstShare],
            "a failed commit must not leave the caller holding shares it sealed"
        )

        // The user disables the passcode and taps again. Against a commit that
        // kept its own seal this throws `.unreadableKeyshare`, permanently.
        state = .disabled
        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)
        XCTAssertEqual(try storedShares(), [firstShare], "read back from the store, not from a pending insert")
    }

    /// "Looks Good" is the retry, so it has to work — and it has to bring the
    /// default coins with it, not just the vault.
    func testARetryAfterAFailedSaveStoresTheVaultAndItsCoins() throws {
        let vault = TestStore.makeDerivableVault(keyshare: firstShare)
        let protector = KeyshareProtector(state: { .disabled })

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: protector,
                save: failingSave
            )
        )

        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)

        let stored = try storedVaults()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(
            Set(stored.first?.coins.map(\.chain) ?? []),
            Set(TestStore.derivableChains),
            "the retry has to attach the default coins, not only store the vault"
        )
        // The undo deliberately leaves the coin preparation's own output alone.
        // Reverting `defiChains` while the rollback leaves the coin objects
        // attached would drop them for good: a preparation that finds coins
        // already there does not recompute the DeFi chains.
        XCTAssertTrue(
            stored.first?.defiChains.contains(.tron) ?? false,
            "the DeFi chains derived alongside the coins have to survive the retry too"
        )
    }

    /// The undo for a vault this commit has to insert is a `rollback()`, and
    /// `rollback()` discards *every* pending change in the context — measured:
    /// a foreign pending insert is destroyed outright and a foreign pending
    /// edit is reverted. `Storage.shared.modelContext` is the app-wide context
    /// and episodes overlap by design, so a commit that could not take its own
    /// work back without taking somebody else's is refused before it starts.
    func testACommitIsRefusedWhileTheStoreIsCarryingWorkItCouldNotTakeBack() throws {
        let foreign = makeVault(name: "Savings", shares: [secondShare])
        Storage.shared.modelContext.insert(foreign)   // never saved

        let vault = makeVault(name: "Treasury", shares: [firstShare])
        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: KeyshareProtector(state: { .disabled }),
                save: failingSave
            )
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .busy)
        }

        XCTAssertEqual(
            try Storage.shared.modelContext.fetch(FetchDescriptor<Vault>()).map(\.name),
            ["Savings"],
            "the refused vault must not even be registered — a pending insert answers every fetch in the app"
        )
        XCTAssertTrue(vault.coins.isEmpty, "and no coins may have been built for it")
        XCTAssertTrue(
            Storage.shared.modelContext.hasChanges,
            "while the work the context was carrying is left exactly where it was"
        )
    }

    /// And the refusal is the transient thing it claims to be: any save settles
    /// the context and the same button then works, completely — coins included.
    func testTheRefusalClearsOnceTheStoreSettles() throws {
        let protector = KeyshareProtector(state: { .disabled })
        Storage.shared.modelContext.insert(makeVault(name: "Savings", shares: [secondShare]))

        let vault = TestStore.makeDerivableVault(keyshare: firstShare)
        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .busy)
        }

        // Anything at all saves the shared context — the main one autosaves.
        try Storage.shared.modelContext.save()

        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)

        let stored = try storedVaults()
        XCTAssertEqual(Set(stored.map(\.name)), ["Savings", vault.name])
        XCTAssertEqual(
            Set(stored.first { $0.name == vault.name }?.coins.map(\.chain) ?? []),
            Set(TestStore.derivableChains),
            "a retry that stores the vault without its chains is the failure this undo exists to avoid"
        )
    }

    /// **Not every vault reaching the commit is new.** A secure reshare on a
    /// device that was already a signer has its reshared vault saved outright by
    /// `finalizeDKLSKeygen`, and still routes through the review screen — where
    /// the screen's own `isBackedUp = false` leaves the context dirty, which is
    /// precisely the branch that withdraws row by row.
    ///
    /// Deleting the vault there does not remove the row — a delete that follows
    /// this call's own no-op `insert` of an already-registered object leaves it
    /// in place — but the `.cascade` on `Vault.coins` runs anyway, so the
    /// reshared wallet comes back with **no chains in it**, silently, because a
    /// re-save failed. Which is why the fixture has to be a vault whose coins
    /// actually build: a placeholder-key vault attaches none, and the cascade
    /// then has nothing to take.
    func testAFailedCommitDoesNotWithdrawAVaultItDidNotInsert() throws {
        let protector = KeyshareProtector(state: { .disabled })
        let vault = TestStore.makeDerivableVault(keyshare: firstShare)

        // The reshare's own save, before the review screen is shown.
        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext, protector: protector)
        vault.isBackedUp = true
        try Storage.shared.modelContext.save()
        XCTAssertEqual(try storedVaults().first?.coins.count, TestStore.derivableChains.count)

        // What the review screen does on the way in, leaving the context dirty.
        vault.isBackedUp = false
        XCTAssertTrue(Storage.shared.modelContext.hasChanges, "the fixture has to reach the coins-only undo")

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: protector,
                save: failingSave
            )
        )

        try Storage.shared.modelContext.save()

        let stored = try storedVaults()
        XCTAssertEqual(stored.count, 1, "an already-stored vault must survive a failed re-commit")
        XCTAssertEqual(
            Set(stored.first?.coins.map(\.chain) ?? []),
            Set(TestStore.derivableChains),
            "and must keep its chains — nothing rebuilds default coins after keygen and import"
        )
        XCTAssertEqual(
            stored.first?.keyshares.map(\.keyshare),
            [firstShare],
            "and its key shares"
        )
    }

    /// The review screen renders `error.localizedDescription`. Without the
    /// `LocalizedError` conformance the user would be shown
    /// "(VultisigApp.KeygenCommitError error 0.)" for a dead vault.
    func testEveryRefusalIsReportedInWordsRatherThanAsAnNSError() {
        let cases: [(KeygenCommitError, String)] = [
            (.unreadableKeyshare(pubkey: "treasury-share-0"), "keysharesUnreadableVaultNotSaved"),
            (.unsealableKeyshare(pubkey: "treasury-share-0"), "keysharesUnsealableVaultNotSaved"),
            (.busy, "somethingWentWrongTryAgain")
        ]

        for (error, key) in cases {
            // `.localized` hands back the key itself when the key is missing, so
            // comparing against `key.localized` alone would pass over an
            // untranslated build. This is what proves the copy actually exists.
            XCTAssertNotEqual(key.localized, key, "\(key) must be present in the bundled locale")

            XCTAssertEqual(error.errorDescription, key.localized)
            XCTAssertEqual(error.localizedDescription, key.localized)
            XCTAssertFalse(
                error.localizedDescription.contains("KeygenCommitError"),
                "the alert must not fall back to the raw NSError form"
            )
        }
    }

    /// The seal is proved to open back before it is stored, and this is the
    /// only way to exercise that: `AesGcmKeyshareCipher` either round-trips or
    /// throws, so nothing built on the real cipher can reach the guard.
    ///
    /// Without the proof this commit stores ciphertext that opens to something
    /// other than the share — a vault that looks complete and signs nothing,
    /// which is the exact outcome the whole check exists to prevent, arrived at
    /// from the other side.
    func testCommitVaultThrowsWhenASealDoesNotOpenBackToWhatWentIn() throws {
        let vault = makeVault(name: "Treasury", shares: [firstShare])

        XCTAssertThrowsError(
            try KeygenViewModel.commitVault(
                vault,
                context: Storage.shared.modelContext,
                protector: SealThatDoesNotOpenBack()
            )
        ) { error in
            XCTAssertEqual(error as? KeygenCommitError, .unsealableKeyshare(pubkey: "treasury-share-0"))
        }
        XCTAssertEqual(try persistedVaultCount(), 0, "a share that cannot be read back must not reach the store")
    }

    /// The two refusals exist because they describe different operations — one
    /// share could not be read back, the other could not be protected — and
    /// pointing both at "could not be read" would make the second one false.
    /// It pins the copy, and only the copy.
    func testTheTwoRefusalsDoNotSayTheSameThing() {
        XCTAssertNotEqual(
            KeygenCommitError.unreadableKeyshare(pubkey: "treasury-share-0").errorDescription,
            KeygenCommitError.unsealableKeyshare(pubkey: "treasury-share-0").errorDescription
        )
    }
}

/// A protector that seals to something `open` will not give back.
///
/// It exists because the production cipher cannot express this: AES-GCM either
/// returns the plaintext it authenticated or throws, so the round-trip proof has
/// no reachable failure on the real wiring — and an unreachable guard that is
/// never exercised is an unverified one.
private struct SealThatDoesNotOpenBack: KeyshareProtecting {

    func isSealed(_ stored: String) -> Bool {
        stored.hasPrefix("vlt2:")
    }

    func seal(_ plaintext: String) throws -> String {
        isSealed(plaintext) ? plaintext : "vlt2:\(plaintext)"
    }

    func open(_ stored: String) throws -> String {
        // Plaintext still passes through, so the share reaches the seal exactly
        // as it would in production and only the proof is what fails.
        guard isSealed(stored) else { return stored }
        return "a different share entirely"
    }
}
