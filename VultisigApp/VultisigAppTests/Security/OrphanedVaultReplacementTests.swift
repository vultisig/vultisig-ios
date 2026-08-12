//
//  OrphanedVaultReplacementTests.swift
//  VultisigAppTests
//

import CryptoKit
import SwiftData
import XCTest
@testable import VultisigApp

/// The recovery route, end to end.
///
/// A device restored without its Keychain holds every key share sealed under a
/// key that is gone. It is told to restore from its `.vult` — and the import
/// gate answered `.duplicate` and skipped it, so the advice was a dead end and
/// the recovery screen came back on every launch forever.
///
/// This re-enables, in one tightly bounded path, the replacement the import gate
/// was hardened against. So the tests here are as much about what must **not**
/// be replaced as about what must: a stored vault holding openable shares, one
/// this device merely cannot read *right now*, and one the import cannot prove
/// it has a working copy of are each a vault that would be destroyed by a
/// looser predicate.
///
/// Every fixture carries real key shares. A suite built on share-less vaults
/// passes while refusing every vault a user actually has — the predicate
/// requires at least one sealed share, so an empty `keyshares` array never
/// qualifies.
@MainActor
final class OrphanedVaultReplacementTests: XCTestCase {

    private var token: TestContextToken!
    private var context: ModelContext!
    private var keychain: MockKeychainService!
    private var keyStore: DefaultKeyshareKeyStore!
    private var lostKey: SymmetricKey!

    /// What the vault's shares really are, and what a good `.vult` carries.
    private let ecdsaShare = "eyJrZXlzaGFyZSI6ImRrbHMtZWNkc2EifQ=="
    private let eddsaShare = "eyJrZXlzaGFyZSI6ImRrbHMtZWRkc2EifQ=="

    private let ecdsaPubKey = "ecdsa-recovered-vault"
    private let eddsaPubKey = "eddsa-recovered-vault"

    override func setUpWithError() throws {
        try super.setUpWithError()
        token = try TestStore.installInMemoryContainer()
        TestStore.retain(token.container)
        context = token.container.mainContext
        keychain = MockKeychainService()
        keyStore = DefaultKeyshareKeyStore(keychain: keychain)
        // The key the previous device held and this one did not inherit. It is
        // never given to anything under test — that is the whole state.
        lostKey = SymmetricKey(size: .bits256)
    }

    override func tearDown() {
        lostKey = nil
        keyStore = nil
        keychain = nil
        context = nil
        TestStore.restore(token)
        token = nil
        super.tearDown()
    }

    // MARK: - The replacement

    /// The route the recovery screen points at, working. The stored row is
    /// replaced by the backup in one save, and what comes back is readable.
    func testAnOrphanedVaultIsReplacedByItsBackup() throws {
        let orphan = try storeOrphanedVault()
        // Captured before the import, because it is what tells an explicit
        // delete-and-insert apart from the upsert this must never rely on: an
        // upsert keeps the stored row and overwrites its values, so the row
        // count and the shares would look exactly the same either way.
        let orphanRow = orphan.persistentModelID
        let sut = makeViewModel()
        sut.decryptedContent = try backupHex()

        sut.restoreVault(modelContext: context, vaults: [orphan])

        XCTAssertTrue(sut.isVaultImported)
        XCTAssertFalse(sut.showAlert)

        // Read back through a context that never saw the objects: the point is
        // what is on disk, and one row rather than two.
        let fresh = ModelContext(token.container)
        let stored = try fresh.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(stored.count, 1, "the orphan is replaced, not joined")
        let replacement = try XCTUnwrap(stored.first)
        XCTAssertEqual(
            Set(replacement.keyshares.map(\.keyshare)),
            Set([ecdsaShare, eddsaShare]),
            "the shares on disk are the backup's, in a form this device can read"
        )
        XCTAssertNotEqual(
            replacement.persistentModelID, orphanRow,
            "the stored row was deleted and a new one inserted, not upserted over"
        )
    }

    /// The name is the backup's own. The row being replaced is on its way out,
    /// so its name is not taken — otherwise every recovery would come back as
    /// "Main (2)".
    func testTheReplacementKeepsTheBackupsName() throws {
        let orphan = try storeOrphanedVault()
        let sut = makeViewModel()
        sut.decryptedContent = try backupHex()

        sut.restoreVault(modelContext: context, vaults: [orphan])

        let fresh = ModelContext(token.container)
        XCTAssertEqual(try XCTUnwrap(try fresh.fetch(FetchDescriptor<Vault>()).first).name, "Main")
    }

    // MARK: - What must not be replaced

    /// The ordinary duplicate, unchanged. A stored vault whose shares open is
    /// not orphaned, and re-importing it must still be skipped rather than
    /// silently rewriting the row.
    func testAnOrdinaryDuplicateIsStillSkipped() throws {
        let stored = try storeVault(shares: [ecdsaShare, eddsaShare])
        let sut = makeViewModel()
        sut.decryptedContent = try backupHex()

        sut.restoreVault(modelContext: context, vaults: [stored])

        XCTAssertFalse(sut.isVaultImported)
        XCTAssertEqual(sut.alertTitle, "vaultAlreadyExists")
        XCTAssertEqual(try ModelContext(token.container).fetchCount(FetchDescriptor<Vault>()), 1)
    }

    /// The one that would destroy a working vault. An unreadable Keychain is not
    /// evidence the key is gone — the item may well be there and open the shares
    /// again on the next launch — so `.unavailable` must not qualify.
    func testAnUnreadableWrapperDoesNotQualify() throws {
        let orphan = try storeOrphanedVault()
        keychain.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)
        let sut = makeViewModel()

        XCTAssertNil(sut.orphanedVault(collidingWith: backupVault(), in: [orphan]))
        XCTAssertEqual(sut.importDecision(for: backupVault(), existing: [orphan]), .duplicate)
    }

    /// A wrapper that is present means the shares are sealed behind a passcode
    /// this device still has. Nothing is orphaned; the app is merely locked.
    func testAPresentWrapperDoesNotQualify() throws {
        let orphan = try storeOrphanedVault()
        keychain.wrappedKeyshareDataKey = Data("wrapped-data-key".utf8)
        let sut = makeViewModel()

        XCTAssertEqual(sut.importDecision(for: backupVault(), existing: [orphan]), .duplicate)
    }

    /// Not a state the app can produce — the sweep is all-or-nothing — so it is
    /// one to refuse rather than to guess about.
    func testAPartlySealedVaultDoesNotQualify() throws {
        let cipher = AesGcmKeyshareCipher()
        let stored = try storeVault(shares: [try cipher.seal(ecdsaShare, with: lostKey), eddsaShare])
        let sut = makeViewModel()

        XCTAssertEqual(sut.importDecision(for: backupVault(), existing: [stored]), .duplicate)
    }

    /// A vault with no shares has nothing to be orphaned about, and treating one
    /// as replaceable is how a suite of share-less fixtures passes while every
    /// real vault is refused.
    func testAVaultWithNoSharesDoesNotQualify() throws {
        let stored = try storeVault(shares: [])
        let sut = makeViewModel()

        XCTAssertEqual(sut.importDecision(for: backupVault(), existing: [stored]), .duplicate)
    }

    /// Matching on one public key is what makes something a duplicate. It is
    /// not enough to make it a replacement: a backup declaring a different
    /// EdDSA key swaps a vault that cannot sign for one that still cannot, and
    /// the ciphertext that was there is gone.
    func testABackupDeclaringADifferentSigningKeyCannotReplaceTheStoredVault() throws {
        let orphan = try storeOrphanedVault()
        let reshared = makeVault(shares: [ecdsaShare, eddsaShare])
        reshared.pubKeyEdDSA = "eddsa-somebody-elses"

        let sut = makeViewModel()

        XCTAssertNil(sut.orphanedVault(collidingWith: reshared, in: [orphan]))
        XCTAssertEqual(sut.importDecision(for: reshared, existing: [orphan]), .duplicate)
    }

    /// The same rule stated where it costs the most, end to end.
    ///
    /// `pubKeyECDSA` and `pubKeyEdDSA` default to `""`, and `""` is a real value
    /// in the unique index. So an incomplete backup matching the orphan on the
    /// one key it carries would, if it qualified, be inserted next to a
    /// perfectly **healthy** vault that also declares no EdDSA key — and
    /// SwiftData would resolve that by upserting over the healthy row, taking
    /// its key shares with it. Deleting the orphan does nothing about that.
    func testAnIncompleteBackupCannotUpsertOverAHealthyVault() throws {
        let orphan = try storeOrphanedVault()
        let healthy = Vault(
            name: "Savings",
            signers: [],
            pubKeyECDSA: "ecdsa-healthy",
            pubKeyEdDSA: "",
            keyshares: [KeyShare(pubkey: "ecdsa-healthy", keyshare: ecdsaShare)],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        context.insert(healthy)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Vault>()), 2)

        let incomplete = Vault(
            name: "Main",
            signers: [],
            pubKeyECDSA: ecdsaPubKey,
            pubKeyEdDSA: "",
            keyshares: [
                KeyShare(pubkey: ecdsaPubKey, keyshare: ecdsaShare),
                KeyShare(pubkey: eddsaPubKey, keyshare: eddsaShare)
            ],
            localPartyID: "iPhone-1",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        let sut = makeViewModel()
        sut.decryptedContent = try JSONEncoder()
            .encode(BackupVault(version: .v1, vault: incomplete))
            .hexString

        sut.restoreVault(modelContext: context, vaults: [orphan, healthy])

        XCTAssertFalse(sut.isVaultImported)
        let fresh = ModelContext(token.container)
        XCTAssertEqual(
            try fresh.fetchCount(FetchDescriptor<Vault>()), 2,
            "both stored vaults survive — the orphan and the one that had nothing to do with it"
        )
    }

    /// A backup declaring a key it carries no share for cannot sign with it, so
    /// it is not a replacement for anything either.
    func testABackupWithNoShareForOneOfItsOwnKeysCannotReplace() throws {
        let orphan = try storeOrphanedVault()
        let overclaiming = makeVault(shares: [ecdsaShare, eddsaShare])
        overclaiming.publicKeyMLDSA44 = "mldsa-with-no-share"

        let sut = makeViewModel()

        XCTAssertNil(sut.orphanedVault(collidingWith: overclaiming, in: [orphan]))
    }

    /// A backup matching two stored vaults is a question this cannot answer, and
    /// answering it by picking one destroys the other's key material.
    func testABackupCollidingWithTwoStoredVaultsDoesNotQualify() throws {
        let cipher = AesGcmKeyshareCipher()
        let onEcdsa = Vault(
            name: "Main",
            signers: [],
            pubKeyECDSA: ecdsaPubKey,
            pubKeyEdDSA: "eddsa-other",
            keyshares: [KeyShare(pubkey: ecdsaPubKey, keyshare: try cipher.seal(ecdsaShare, with: lostKey))],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        let onEddsa = Vault(
            name: "Spare",
            signers: [],
            pubKeyECDSA: "ecdsa-other",
            pubKeyEdDSA: eddsaPubKey,
            keyshares: [KeyShare(pubkey: eddsaPubKey, keyshare: try cipher.seal(eddsaShare, with: lostKey))],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        context.insert(onEcdsa)
        context.insert(onEddsa)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Vault>()), 2, "distinct key material, so two rows")

        let sut = makeViewModel()

        XCTAssertNil(sut.orphanedVault(collidingWith: backupVault(), in: [onEcdsa, onEddsa]))
    }

    /// The other side of the trade, and the one a replacement makes newly
    /// dangerous. `ProtectedVaultImporter` proves that whatever the backup
    /// *carries* opens here — but a file carrying nothing at all normalizes
    /// perfectly well, so without this it would delete the orphan in exchange
    /// for a vault that can sign nothing.
    func testABackupWithNoKeySharesCannotReplaceAnything() throws {
        let orphan = try storeOrphanedVault()
        let empty = makeVault(shares: [])
        XCTAssertTrue(empty.keyshares.isEmpty, "precondition: the backup carries no key material")

        let sut = makeViewModel()

        XCTAssertNil(sut.orphanedVault(collidingWith: empty, in: [orphan]))
        XCTAssertEqual(sut.importDecision(for: empty, existing: [orphan]), .duplicate)
    }

    /// Less key material than the row it displaces is not a replacement for it.
    /// A backup holding only the ECDSA share would take the EdDSA one with the
    /// orphan, and nothing would ever bring it back.
    func testABackupMissingOneOfTheStoredSharesCannotReplaceIt() throws {
        let orphan = try storeOrphanedVault()
        let partial = makeVault(shares: [ecdsaShare])
        XCTAssertEqual(partial.keyshares.count, 1, "precondition: one share where the stored vault holds two")

        let sut = makeViewModel()

        XCTAssertNil(sut.orphanedVault(collidingWith: partial, in: [orphan]))
    }

    /// An empty string is a share the store will happily hold and nothing can
    /// ever sign with.
    func testABackupCarryingAnEmptyShareCannotReplaceAnything() throws {
        let orphan = try storeOrphanedVault()
        let blank = makeVault(shares: [ecdsaShare, ""])

        let sut = makeViewModel()

        XCTAssertNil(sut.orphanedVault(collidingWith: blank, in: [orphan]))
    }

    /// One incoming vault per orphan, across a whole ZIP.
    ///
    /// A ZIP holding the same vault twice is the shape a user actually produces
    /// — two exports of the same vault, or the same file under two names. The
    /// first replaces the orphan; the second must be skipped as a duplicate
    /// rather than replacing a row that is already being replaced.
    func testTwoCopiesOfTheSameVaultInOneZipReplaceTheOrphanOnce() throws {
        let orphan = try storeOrphanedVault()

        let sut = makeViewModel()
        sut.multipleVaultsToImport = [backupVault(), backupVault()]

        sut.restoreMultipleVaults(modelContext: context, vaults: [orphan])

        let fresh = ModelContext(token.container)
        XCTAssertEqual(
            try fresh.fetchCount(FetchDescriptor<Vault>()), 1,
            "the orphan is gone and exactly one replacement took its place"
        )
        XCTAssertTrue(sut.showAlert, "the skipped copy is reported rather than silently dropped")
    }

    // MARK: - When the replacement does not land

    /// The deletion and the insert are one save, so a save that fails leaves the
    /// orphan exactly where it was. Losing it here would take the user's only
    /// remaining copy of that key material with it — and they would not have a
    /// working vault to show for it.
    func testAFailedSaveLeavesTheOrphanInPlace() throws {
        let orphan = try storeOrphanedVault()
        let sealedBefore = orphan.keyshares.map(\.keyshare)

        let sut = makeViewModel(save: { _ in throw SaveFailure.refused })
        sut.decryptedContent = try backupHex()

        sut.restoreVault(modelContext: context, vaults: [orphan])

        XCTAssertFalse(sut.isVaultImported)
        XCTAssertEqual(sut.alertTitle, "vaultRestoreFailed")

        let fresh = ModelContext(token.container)
        let stored = try fresh.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(stored.first).keyshares.map(\.keyshare), sealedBefore,
            "the orphan survives the failure with its own shares, not the backup's"
        )
    }

    /// A pending deletion cannot be withdrawn row by row, so a replacement over
    /// a context carrying somebody else's work would leave the orphan on its way
    /// out with nothing arriving in its place the moment that save fails. It is
    /// refused instead, and the user retries.
    func testAReplacementIsRefusedWhileTheStoreCarriesOtherWork() throws {
        let orphan = try storeOrphanedVault()
        let importer = ProtectedVaultImporter(
            protector: KeyshareProtector(state: { .disabled }),
            coordinator: KeyshareWriteCoordinator()
        )

        // Somebody else's unsaved work, which `rollback()` would throw away.
        context.insert(
            Vault(
                name: "Somebody else's half-finished keygen",
                signers: [],
                pubKeyECDSA: "ecdsa-unrelated",
                pubKeyEdDSA: "eddsa-unrelated",
                keyshares: [],
                localPartyID: "party",
                hexChainCode: "hex",
                resharePrefix: nil,
                libType: .DKLS
            )
        )
        XCTAssertTrue(context.hasChanges)

        XCTAssertThrowsError(
            try importer.commit([backupVault()], replacing: [orphan], into: context)
        ) { error in
            XCTAssertEqual(error as? ProtectedVaultImportError, .busy)
        }

        context.rollback()
        let fresh = ModelContext(token.container)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Vault>()), 1, "the orphan is untouched")
    }

    /// A backup this device cannot open must be refused **while the row it would
    /// have replaced is still there**. Normalization runs ahead of the deletion
    /// precisely so a wrong file cannot cost the user the only copy they had.
    func testABackupThatCannotBeOpenedIsRefusedWithoutTouchingTheOrphan() throws {
        let orphan = try storeOrphanedVault()
        let foreign = try AesGcmKeyshareCipher().seal(ecdsaShare, with: SymmetricKey(size: .bits256))
        let importer = ProtectedVaultImporter(
            protector: KeyshareProtector(state: { .disabled }),
            coordinator: KeyshareWriteCoordinator()
        )

        XCTAssertThrowsError(
            try importer.commit([backupVault(shares: [foreign])], replacing: [orphan], into: context)
        )

        let fresh = ModelContext(token.container)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Vault>()), 1)
        XCTAssertEqual(try XCTUnwrap(try fresh.fetch(FetchDescriptor<Vault>()).first).keyshares.count, 2)
    }

    // MARK: - Helpers

    private enum SaveFailure: Error {
        case refused
    }

    private func makeViewModel(
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) -> EncryptedBackupViewModel {
        // `.disabled` is the protection state of a device with no wrapper, which
        // is the state this whole path is about — and the only one the test
        // bundle can drive, since it holds no Keychain entitlement.
        let protector = KeyshareProtector(state: { .disabled })
        return EncryptedBackupViewModel(
            importer: ProtectedVaultImporter(
                protector: protector,
                coordinator: KeyshareWriteCoordinator(),
                save: save
            ),
            protector: protector,
            keyStore: keyStore
        )
    }

    /// One vault's worth of key material, however its shares are stored.
    private func makeVault(shares: [String]) -> Vault {
        Vault(
            name: "Main",
            signers: ["iPhone-1", "iPad-2"],
            pubKeyECDSA: ecdsaPubKey,
            pubKeyEdDSA: eddsaPubKey,
            keyshares: zip([ecdsaPubKey, eddsaPubKey], shares).map { KeyShare(pubkey: $0, keyshare: $1) },
            localPartyID: "iPhone-1",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    /// The vault as the backup carries it: same key material, shares in the
    /// clear, which is what `Vault.mapToProtobuff` writes.
    private func backupVault(shares: [String]? = nil) -> Vault {
        makeVault(shares: shares ?? [ecdsaShare, eddsaShare])
    }

    private func backupHex() throws -> String {
        try JSONEncoder().encode(BackupVault(version: .v1, vault: backupVault())).hexString
    }

    /// The state a restore without the Keychain leaves behind: the vault is
    /// there, every share is `vlt2:` ciphertext, and nothing on the device holds
    /// the key.
    @discardableResult
    private func storeOrphanedVault() throws -> Vault {
        let cipher = AesGcmKeyshareCipher()
        let vault = try storeVault(
            shares: [
                try cipher.seal(ecdsaShare, with: lostKey),
                try cipher.seal(eddsaShare, with: lostKey)
            ]
        )
        XCTAssertEqual(keyStore.loadWrappedDataKey(), .absent, "precondition: the key really is gone")
        return vault
    }

    @discardableResult
    private func storeVault(shares: [String]) throws -> Vault {
        let vault = makeVault(shares: shares)
        context.insert(vault)
        try context.save()
        // A SwiftData `@Attribute(.unique)` collision upserts rather than
        // failing, so a fixture that silently collapsed to one row would pass
        // assertions it never actually exercised.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Vault>()), 1)
        return vault
    }
}
