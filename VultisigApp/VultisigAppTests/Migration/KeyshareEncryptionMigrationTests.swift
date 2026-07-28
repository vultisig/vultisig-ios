//
//  KeyshareEncryptionMigrationTests.swift
//  VultisigAppTests
//

import CryptoKit
import SwiftData
import XCTest
@testable import VultisigApp

/// The migration that rewrites key material. Every test here exists to pin one
/// property: **a failure must leave the plaintext untouched.** A half-converted
/// vault is lost funds, so "it threw" is not enough — the shares have to still
/// be readable afterwards.
@MainActor
final class KeyshareEncryptionMigrationTests: XCTestCase {

    private var container: ModelContainer!
    private var keychain: MockKeychainService!
    private var keyStore: DefaultKeyshareKeyStore!
    private var session: KeyshareKeySession!
    private var protector: KeyshareProtector!

    private let gg20Share = #"{"PubKey":"02aaa","ShareID":{"value":"1"}}"#
    private let dklsShare = "eyJrZXlzaGFyZSI6ImRrbHMifQ=="
    private let mldsaShare = "bWxkc2Eta2V5c2hhcmUtYmxvYg=="

    override func setUpWithError() throws {
        try super.setUpWithError()

        container = try ModelContainer(
            for: Vault.self, Coin.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        Storage.shared.modelContext = container.mainContext

        keychain = MockKeychainService()
        let store = DefaultKeyshareKeyStore(keychain: keychain)
        let keySession = KeyshareKeySession(store: store)
        keyStore = store
        session = keySession
        protector = KeyshareProtector(state: { keySession.currentState() })
    }

    override func tearDown() {
        protector = nil
        session = nil
        keyStore = nil
        keychain = nil
        Storage.shared.modelContext = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeMigration() -> KeyshareEncryptionMigration {
        KeyshareEncryptionMigration(keyStore: keyStore, session: session, protector: protector)
    }

    /// Every unique-attributed field has to differ per vault. `pubKeyEdDSA` is
    /// `@Attribute(.unique)` and defaults to `""`, so leaving it unset makes
    /// SwiftData treat each insert as an upsert on the same key and silently
    /// replace the previous vault — tests then pass vacuously against a store
    /// holding one row.
    @discardableResult
    private func insertVault(name: String, shares: [(String, String)]) -> Vault {
        let vault = Vault(name: name)
        vault.pubKeyECDSA = shares.first?.0 ?? "ecdsa-\(name)"
        vault.pubKeyEdDSA = "eddsa-\(name)"
        vault.localPartyID = "iPhone-\(name)"
        vault.keyshares = shares.map { KeyShare(pubkey: $0.0, keyshare: $0.1) }
        container.mainContext.insert(vault)
        return vault
    }

    private func fetchVaults() throws -> [Vault] {
        try container.mainContext.fetch(FetchDescriptor<Vault>()).sorted { $0.name < $1.name }
    }

    /// Positional indexing into the fetch result is a trap — the order is
    /// alphabetical, not insertion order — so tests address vaults by name.
    private func fetchVault(_ name: String) throws -> Vault {
        let vault = try container.mainContext
            .fetch(FetchDescriptor<Vault>())
            .first { $0.name == name }
        return try XCTUnwrap(vault, "No vault named \(name)")
    }

    private func storedShares(of name: String) throws -> [String] {
        try fetchVault(name).keyshares.map(\.keyshare)
    }

    // MARK: - Happy path

    func testSealsSharesAcrossEveryVaultType() throws {
        insertVault(name: "gg20", shares: [("02aaa", gg20Share)])
        insertVault(name: "dkls", shares: [("02bbb", dklsShare), ("03ccc", dklsShare)])
        insertVault(name: "mldsa", shares: [("02ddd", dklsShare), ("04eee", mldsaShare)])

        try makeMigration().migrate()

        // Asserted so a unique-constraint collision cannot make the loop below
        // pass by iterating an almost-empty store.
        XCTAssertEqual(try fetchVaults().count, 3)
        for vault in try fetchVaults() {
            for share in vault.keyshares {
                XCTAssertTrue(
                    share.keyshare.hasPrefix(AesGcmKeyshareCipher.sealedPrefix),
                    "\(vault.name) still holds a plaintext share"
                )
            }
        }
    }

    func testSealedSharesOpenBackToTheOriginals() throws {
        insertVault(name: "gg20", shares: [("02aaa", gg20Share)])
        insertVault(name: "mixed", shares: [("02bbb", dklsShare), ("04ccc", mldsaShare)])

        try makeMigration().migrate()

        let mixed = try fetchVault("mixed")
        XCTAssertEqual(try mixed.keyshareValue(for: "02bbb", protector: protector), dklsShare)
        XCTAssertEqual(try mixed.keyshareValue(for: "04ccc", protector: protector), mldsaShare)
        XCTAssertEqual(try fetchVault("gg20").keyshareValue(for: "02aaa", protector: protector), gg20Share)
    }

    func testStoresTheDataKeyDurably() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare)])

        try makeMigration().migrate()

        XCTAssertNotNil(keyStore.loadDataKey())
    }

    func testEmptyStoreDoesNotCreateADataKey() throws {
        try makeMigration().migrate()

        XCTAssertNil(keyStore.loadDataKey(), "No vaults means nothing to protect")
    }

    func testVaultWithNoSharesIsHarmless() throws {
        insertVault(name: "empty", shares: [])

        try makeMigration().migrate()

        XCTAssertTrue(try fetchVault("empty").keyshares.isEmpty)
    }

    // MARK: - Idempotency

    func testRunningTwiceIsANoOp() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare), ("03bbb", gg20Share)])
        try makeMigration().migrate()
        let afterFirst = try storedShares(of: "one")

        try makeMigration().migrate()

        XCTAssertEqual(try storedShares(of: "one"), afterFirst, "Second run must not re-seal")
    }

    func testResumesAPartiallyMigratedStore() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare)])
        try makeMigration().migrate()
        // A second vault arrives still in the clear, as if the first run died.
        insertVault(name: "two", shares: [("03bbb", gg20Share)])

        try makeMigration().migrate()

        XCTAssertEqual(try fetchVault("one").keyshareValue(for: "02aaa", protector: protector), dklsShare)
        XCTAssertEqual(try fetchVault("two").keyshareValue(for: "03bbb", protector: protector), gg20Share)
    }

    func testReusesAnExistingDataKeyRatherThanReplacingIt() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare)])
        try makeMigration().migrate()
        let original = keyStore.loadDataKey()?.withUnsafeBytes { Data($0) }

        insertVault(name: "two", shares: [("03bbb", gg20Share)])
        try makeMigration().migrate()

        // Replacing the key would orphan everything the first run sealed.
        XCTAssertEqual(keyStore.loadDataKey()?.withUnsafeBytes { Data($0) }, original)
    }

    // MARK: - Failure leaves plaintext intact

    func testKeychainWriteFailureLeavesEveryShareInTheClear() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare), ("03bbb", gg20Share)])
        keychain.dropsKeyshareDataKeyWrites = true

        XCTAssertThrowsError(try makeMigration().migrate()) { error in
            XCTAssertEqual(error as? KeyshareKeyStoreError, .persistenceFailed)
        }

        XCTAssertEqual(try storedShares(of: "one"), [dklsShare, gg20Share], "Plaintext must survive a failed key write")
    }

    func testVerificationFailureLeavesEveryShareInTheClear() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare), ("03bbb", gg20Share)])
        let migration = KeyshareEncryptionMigration(
            keyStore: keyStore,
            session: session,
            protector: CorruptingProtector(inner: protector)
        )

        XCTAssertThrowsError(try migration.migrate()) { error in
            XCTAssertEqual(
                error as? KeyshareEncryptionMigration.MigrationError,
                .verificationFailed(pubkey: "02aaa")
            )
        }

        XCTAssertEqual(try storedShares(of: "one"), [dklsShare, gg20Share], "Plaintext must survive a failed round trip")
    }

    /// A vault that fails verification must not leave its *other* shares
    /// converted — a vault half in the clear and half sealed is the worst state
    /// to be in, because neither the retry nor the reader knows what to expect.
    func testAVaultIsNeverLeftHalfConverted() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare), ("03bbb", gg20Share), ("04ccc", mldsaShare)])
        let migration = KeyshareEncryptionMigration(
            keyStore: keyStore,
            session: session,
            protector: CorruptingProtector(inner: protector, failingPubkeyIndex: 2)
        )

        XCTAssertThrowsError(try migration.migrate())

        let shares = try storedShares(of: "one")
        XCTAssertEqual(shares, [dklsShare, gg20Share, mldsaShare])
        for share in shares {
            XCTAssertFalse(share.hasPrefix(AesGcmKeyshareCipher.sealedPrefix))
        }
    }

    /// The guarantee is store-wide, not per-vault: a vault that verified must
    /// not be left mutated in the live context because a *later* vault failed.
    /// The migration version stays un-bumped either way, but an autosave or any
    /// unrelated save could otherwise flush that half-migrated state to disk.
    func testFailureInOneVaultLeavesEveryOtherVaultInTheClear() throws {
        insertVault(name: "aaa", shares: [("02aaa", dklsShare)])
        insertVault(name: "bbb", shares: [("03bbb", gg20Share)])
        insertVault(name: "ccc", shares: [("04ccc", mldsaShare)])
        // Fails on the third share, i.e. after the first two vaults verified.
        let migration = KeyshareEncryptionMigration(
            keyStore: keyStore,
            session: session,
            protector: CorruptingProtector(inner: protector, failingPubkeyIndex: 2)
        )

        XCTAssertThrowsError(try migration.migrate())

        XCTAssertEqual(try storedShares(of: "aaa"), [dklsShare])
        XCTAssertEqual(try storedShares(of: "bbb"), [gg20Share])
        XCTAssertEqual(try storedShares(of: "ccc"), [mldsaShare])
    }

    // MARK: - Persistence

    /// Reading back through the same context proves nothing about persistence:
    /// the objects are identical instances, so an in-memory mutation that
    /// SwiftData never marked dirty would still look correct. This writes to
    /// disk, tears the container down, and reopens it.
    func testSealedSharesSurviveAStoreRoundTrip() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyshare-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        var diskContainer: ModelContainer? = try ModelContainer(
            for: Vault.self, Coin.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        Storage.shared.modelContext = try XCTUnwrap(diskContainer).mainContext

        let vault = Vault(name: "persisted")
        vault.pubKeyECDSA = "02aaa"
        vault.pubKeyEdDSA = "eddsa-persisted"
        vault.localPartyID = "iPhone-persisted"
        vault.keyshares = [
            KeyShare(pubkey: "02aaa", keyshare: dklsShare),
            KeyShare(pubkey: "03bbb", keyshare: gg20Share)
        ]
        try XCTUnwrap(diskContainer).mainContext.insert(vault)

        try makeMigration().migrate()

        // Drop everything and reopen from disk.
        Storage.shared.modelContext = nil
        diskContainer = nil

        let reopened = try ModelContainer(
            for: Vault.self, Coin.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let restored = try XCTUnwrap(
            reopened.mainContext.fetch(FetchDescriptor<Vault>()).first { $0.name == "persisted" }
        )

        for share in restored.keyshares {
            XCTAssertTrue(
                share.keyshare.hasPrefix(AesGcmKeyshareCipher.sealedPrefix),
                "Sealed shares must reach the persistent store, not just the context"
            )
        }
        XCTAssertEqual(try restored.keyshareValue(for: "02aaa", protector: protector), dklsShare)
        XCTAssertEqual(try restored.keyshareValue(for: "03bbb", protector: protector), gg20Share)
    }

    func testSharesStayReadableAfterAFailedMigration() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare)])
        keychain.dropsKeyshareDataKeyWrites = true

        XCTAssertThrowsError(try makeMigration().migrate())

        XCTAssertEqual(try fetchVault("one").keyshareValue(for: "02aaa", protector: protector), dklsShare)
    }

    // MARK: - Never replace a data key that sealed shares depend on

    /// `loadDataKey` returns nil for any failure, not only for an absent item,
    /// and `AppMigrationService` reads its version from the same Keychain — so a
    /// transient Keychain failure can re-run a finished migration *and* hide the
    /// key. Generating a replacement then would orphan every sealed share
    /// permanently, so the migration must abort and retry on the next launch.
    func testAbortsRatherThanReplaceAMissingDataKeyWhenSharesAreSealed() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare)])
        try makeMigration().migrate()
        let sealedBefore = try storedShares(of: "one")
        // Simulate the Keychain read failing: the key vanishes, shares stay sealed.
        keychain.setKeyshareDataKey(nil)
        session.clear()

        XCTAssertThrowsError(try makeMigration().migrate()) { error in
            XCTAssertEqual(error as? KeyshareEncryptionMigration.MigrationError, .dataKeyUnavailable)
        }

        XCTAssertNil(keychain.getKeyshareDataKey(), "A replacement key would orphan the sealed shares")
        XCTAssertEqual(try storedShares(of: "one"), sealedBefore)
    }

    func testStillCreatesAKeyWhenNothingIsSealedYet() throws {
        insertVault(name: "one", shares: [("02aaa", dklsShare)])

        try makeMigration().migrate()

        XCTAssertNotNil(keyStore.loadDataKey())
    }

    /// An already-sealed share must be authenticated, not assumed good. One
    /// sealed under a key we no longer hold would otherwise ride through, let
    /// the migration report success and bump its version, and leave the vault
    /// dead with nothing ever revisiting it.
    func testAbortsWhenAnExistingSealedShareCannotBeOpened() throws {
        let foreignKey = try VaultCryptoEnvelope.randomKey()
        let orphaned = try AesGcmKeyshareCipher().seal(dklsShare, with: foreignKey)
        insertVault(name: "one", shares: [("02aaa", orphaned), ("03bbb", gg20Share)])
        // A usable data key exists, but it is not the one that sealed the share.
        try keyStore.storeDataKey(try keyStore.generateDataKey())

        XCTAssertThrowsError(try makeMigration().migrate()) { error in
            XCTAssertEqual(
                error as? KeyshareEncryptionMigration.MigrationError,
                .verificationFailed(pubkey: "02aaa")
            )
        }

        XCTAssertEqual(try storedShares(of: "one"), [orphaned, gg20Share], "Nothing may be rewritten")
    }

    func testMissingModelContextThrowsWithoutSideEffects() {
        Storage.shared.modelContext = nil

        XCTAssertThrowsError(try makeMigration().migrate()) { error in
            XCTAssertEqual(error as? KeyshareEncryptionMigration.MigrationError, .missingModelContext)
        }
        XCTAssertNil(keyStore.loadDataKey())
    }
}

/// Seals correctly but opens to the wrong value, standing in for any reason a
/// round trip might not reproduce the original.
///
/// A class, not a struct, so its call counter is per-instance — a shared static
/// would leak between tests and make the failure index meaningless.
private final class CorruptingProtector: KeyshareProtecting {

    private let inner: KeyshareProtecting
    /// Which sealed share to corrupt on open; every one when nil.
    private let failingPubkeyIndex: Int?
    private let cipher = AesGcmKeyshareCipher()
    private let lock = NSLock()
    private var openCount = -1

    init(inner: KeyshareProtecting, failingPubkeyIndex: Int? = nil) {
        self.inner = inner
        self.failingPubkeyIndex = failingPubkeyIndex
    }

    func isSealed(_ stored: String) -> Bool {
        cipher.isSealed(stored)
    }

    func seal(_ plaintext: String) throws -> String {
        try inner.seal(plaintext)
    }

    func open(_ stored: String) throws -> String {
        guard cipher.isSealed(stored) else {
            return try inner.open(stored)
        }

        lock.lock()
        openCount += 1
        let index = openCount
        lock.unlock()

        if let failingPubkeyIndex, index != failingPubkeyIndex {
            return try inner.open(stored)
        }
        return "not-the-original-share"
    }
}
