//
//  ZipImportDuplicateTests.swift
//  VultisigAppTests
//
//  Duplicate and unique-attribute collision handling during vault import.
//
//  `Vault` marks `name`, `pubKeyECDSA`, `pubKeyEdDSA` and `publicKeyMLDSA44`
//  `@Attribute(.unique)`, and SwiftData turns a colliding insert into an
//  *upsert* — the incoming vault replaces the stored one and takes its key
//  shares with it. These tests pin both halves of the gate: "is this a
//  duplicate?" and "can this be stored without clobbering something?".
//

import XCTest
import SwiftData
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class ZipImportDuplicateTests: XCTestCase {

    private var viewModel: EncryptedBackupViewModel!

    override func setUp() {
        super.setUp()
        viewModel = EncryptedBackupViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - isVaultUnique

    func testIsVaultUnique_withNoExistingVaults_returnsTrue() {
        let vault = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2")
        XCTAssertTrue(viewModel.isVaultUnique(backupVault: vault, vaults: []))
    }

    func testIsVaultUnique_withDifferentVaults_returnsTrue() {
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2")
        let newVault = makeVault(name: "Vault B", ecdsa: "key3", eddsa: "key4")
        XCTAssertTrue(viewModel.isVaultUnique(backupVault: newVault, vaults: [existing]))
    }

    func testIsVaultUnique_withMatchingKeys_returnsFalse() {
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2")
        let duplicate = makeVault(name: "Vault A Copy", ecdsa: "key1", eddsa: "key2")
        XCTAssertFalse(viewModel.isVaultUnique(backupVault: duplicate, vaults: [existing]))
    }

    func testIsVaultUnique_withPartialKeyMatch_returnsFalse() {
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2")
        // Same ECDSA, different EdDSA. A vault cannot legitimately share one key
        // with a different vault, and `pubKeyECDSA` is `@Attribute(.unique)` — so
        // inserting this would upsert the stored vault's key shares away. Treated
        // as a duplicate and rejected.
        let partial = makeVault(name: "Vault B", ecdsa: "key1", eddsa: "key999")
        XCTAssertFalse(viewModel.isVaultUnique(backupVault: partial, vaults: [existing]))
    }

    func testIsVaultUniqueRejectsEddsaOnlyCollision() {
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2")
        let partial = makeVault(name: "Vault B", ecdsa: "key999", eddsa: "key2")
        XCTAssertFalse(viewModel.isVaultUnique(backupVault: partial, vaults: [existing]))
    }

    func testIsVaultUniqueRejectsMldsaOnlyCollision() {
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2", mldsa: "quantum1")
        let partial = makeVault(name: "Vault B", ecdsa: "key3", eddsa: "key4", mldsa: "quantum1")
        XCTAssertFalse(viewModel.isVaultUnique(backupVault: partial, vaults: [existing]))
    }

    func testIsVaultUniqueTreatsNilMldsaAsNoIdentity() {
        // Every non-quantum vault has a nil MLDSA key; that must not make them
        // all duplicates of each other.
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2")
        let other = makeVault(name: "Vault B", ecdsa: "key3", eddsa: "key4")
        XCTAssertNil(existing.publicKeyMLDSA44)
        XCTAssertTrue(viewModel.isVaultUnique(backupVault: other, vaults: [existing]))
    }

    func testIsVaultUniqueTreatsEmptyPubkeysAsNoIdentity() {
        // `""` is the default for both keys. It says nothing about identity, so
        // it is not evidence of duplication — whether it is safe to *store* is a
        // separate question, answered by `importDecision`.
        let existing = makeVault(name: "Vault A", ecdsa: "", eddsa: "")
        let other = makeVault(name: "Vault B", ecdsa: "", eddsa: "")
        XCTAssertTrue(viewModel.isVaultUnique(backupVault: other, vaults: [existing]))
    }

    func testIsVaultUniqueTreatsEmptyMldsaAsNoIdentity() {
        // The JSON backup path decodes `publicKeyMLDSA44` verbatim, so `""` can
        // reach here where the proto path would have produced `nil`.
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2", mldsa: "")
        let other = makeVault(name: "Vault B", ecdsa: "key3", eddsa: "key4", mldsa: "")
        XCTAssertTrue(viewModel.isVaultUnique(backupVault: other, vaults: [existing]))
    }

    // MARK: - importDecision

    func testImportDecisionKeepsTheBackupNameWhenItIsFree() {
        let existing = makeVault(name: "Savings", ecdsa: "key1", eddsa: "key2")
        let incoming = makeVault(name: "Holidays", ecdsa: "key3", eddsa: "key4")

        XCTAssertEqual(
            viewModel.importDecision(for: incoming, existing: [existing]),
            .insert(name: "Holidays")
        )
    }

    func testImportDecisionRenamesOnANameOnlyCollision() {
        let existing = makeVault(name: "Savings", ecdsa: "key1", eddsa: "key2")
        let incoming = makeVault(name: "Savings", ecdsa: "key3", eddsa: "key4")

        // Genuinely different key material: admit it under a non-colliding name
        // rather than let SwiftData replace the stored vault.
        XCTAssertEqual(
            viewModel.importDecision(for: incoming, existing: [existing]),
            .insert(name: "Savings (2)")
        )
    }

    func testImportDecisionWalksPastAlreadyTakenSuffixes() {
        let existing = [
            makeVault(name: "Savings", ecdsa: "key1", eddsa: "key2"),
            makeVault(name: "Savings (2)", ecdsa: "key3", eddsa: "key4")
        ]
        let incoming = makeVault(name: "Savings", ecdsa: "key5", eddsa: "key6")

        XCTAssertEqual(
            viewModel.importDecision(for: incoming, existing: existing),
            .insert(name: "Savings (3)")
        )
    }

    func testImportDecisionReportsDuplicateOnBothKeysMatching() {
        let existing = makeVault(name: "Savings", ecdsa: "key1", eddsa: "key2")
        let incoming = makeVault(name: "Savings Copy", ecdsa: "key1", eddsa: "key2")

        XCTAssertEqual(viewModel.importDecision(for: incoming, existing: [existing]), .duplicate)
    }

    func testImportDecisionReportsDuplicateOnEcdsaOnlyMatch() {
        let existing = makeVault(name: "Savings", ecdsa: "key1", eddsa: "key2")
        let incoming = makeVault(name: "Holidays", ecdsa: "key1", eddsa: "key999")

        XCTAssertEqual(viewModel.importDecision(for: incoming, existing: [existing]), .duplicate)
    }

    func testImportDecisionReportsDuplicateOnEddsaOnlyMatch() {
        let existing = makeVault(name: "Savings", ecdsa: "key1", eddsa: "key2")
        let incoming = makeVault(name: "Holidays", ecdsa: "key999", eddsa: "key2")

        XCTAssertEqual(viewModel.importDecision(for: incoming, existing: [existing]), .duplicate)
    }

    func testImportDecisionReportsDuplicateOnMldsaOnlyMatch() {
        let existing = makeVault(name: "Savings", ecdsa: "key1", eddsa: "key2", mldsa: "quantum1")
        let incoming = makeVault(name: "Holidays", ecdsa: "key3", eddsa: "key4", mldsa: "quantum1")

        XCTAssertEqual(viewModel.importDecision(for: incoming, existing: [existing]), .duplicate)
    }

    func testImportDecisionRefusesAnEmptyPubkeyCollision() {
        // Two key-less backups are not recognisably the same vault, but `""` is a
        // real value in the unique index, so storing the second would upsert the
        // first. Refuse rather than overwrite.
        let existing = makeVault(name: "Broken A", ecdsa: "", eddsa: "")
        let incoming = makeVault(name: "Broken B", ecdsa: "", eddsa: "")

        XCTAssertEqual(viewModel.importDecision(for: incoming, existing: [existing]), .unsafeCollision)
    }

    func testImportDecisionRefusesAnEmptyEddsaCollisionAlone() {
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "")
        let incoming = makeVault(name: "Vault B", ecdsa: "key2", eddsa: "")

        XCTAssertEqual(viewModel.importDecision(for: incoming, existing: [existing]), .unsafeCollision)
    }

    func testImportDecisionAdmitsAnEmptyPubkeyVaultWhenNothingCollides() {
        let existing = makeVault(name: "Savings", ecdsa: "key1", eddsa: "key2")
        let incoming = makeVault(name: "Broken", ecdsa: "", eddsa: "")

        XCTAssertEqual(
            viewModel.importDecision(for: incoming, existing: [existing]),
            .insert(name: "Broken")
        )
    }

    // MARK: - availableVaultName

    func testAvailableVaultNameReturnsTheNameWhenFree() {
        XCTAssertEqual(viewModel.availableVaultName(basedOn: "Savings", taken: ["Holidays"]), "Savings")
    }

    func testAvailableVaultNameTerminatesOnALongCollisionChain() {
        var taken: Set<String> = ["Savings"]
        for suffix in 2...50 {
            taken.insert("Savings (\(suffix))")
        }

        XCTAssertEqual(viewModel.availableVaultName(basedOn: "Savings", taken: taken), "Savings (51)")
    }

    // MARK: - showImportResults

    func testShowImportResults_allNew_setsImportedSuccessfully() {
        let vault = makeVault(name: "Vault A", ecdsa: "k1", eddsa: "k2")
        let results: EncryptedBackupViewModel.ImportResults = (
            imported: [vault],
            duplicates: 0,
            skippedNames: [],
            unsafeNames: []
        )

        viewModel.showImportResults(results)

        XCTAssertTrue(viewModel.isVaultImported)
        XCTAssertFalse(viewModel.showAlert)
        XCTAssertEqual(viewModel.alertTitle, "vaultImportedSuccessfully")
    }

    func testShowImportResults_multipleAllNew_setsVaultsImportedSuccessfully() {
        let v1 = makeVault(name: "V1", ecdsa: "k1", eddsa: "k2")
        let v2 = makeVault(name: "V2", ecdsa: "k3", eddsa: "k4")
        let results: EncryptedBackupViewModel.ImportResults = (
            imported: [v1, v2],
            duplicates: 0,
            skippedNames: [],
            unsafeNames: []
        )

        viewModel.showImportResults(results)

        XCTAssertTrue(viewModel.isVaultImported)
        XCTAssertFalse(viewModel.showAlert)
        XCTAssertEqual(viewModel.alertTitle, "vaultsImportedSuccessfully")
    }

    func testShowImportResults_mixed_showsPartialSuccess() {
        let imported = makeVault(name: "New Vault", ecdsa: "k1", eddsa: "k2")
        let results: EncryptedBackupViewModel.ImportResults = (
            imported: [imported],
            duplicates: 1,
            skippedNames: ["Old Vault"],
            unsafeNames: []
        )

        viewModel.showImportResults(results)

        XCTAssertTrue(viewModel.isVaultImported, "Should still mark as imported when some vaults succeeded")
        XCTAssertTrue(viewModel.showAlert, "Should show alert with details about skipped vaults")
        XCTAssertTrue(viewModel.alertTitle.contains("Old Vault"), "Alert should mention the skipped vault name")
    }

    func testShowImportResults_allDuplicates_showsInfoNotError() {
        let results: EncryptedBackupViewModel.ImportResults = (
            imported: [],
            duplicates: 2,
            skippedNames: ["Vault A", "Vault B"],
            unsafeNames: []
        )

        viewModel.showImportResults(results)

        XCTAssertFalse(viewModel.isVaultImported, "Should not mark as imported when all are duplicates")
        XCTAssertTrue(viewModel.showAlert, "Should show informational alert")
        XCTAssertTrue(viewModel.alertTitle.contains("Vault A"), "Alert should list skipped vault names")
        XCTAssertTrue(viewModel.alertTitle.contains("Vault B"), "Alert should list skipped vault names")
    }

    func testShowImportResults_noneImportedNoDuplicates_showsRestoreFailed() {
        let results: EncryptedBackupViewModel.ImportResults = (
            imported: [],
            duplicates: 0,
            skippedNames: [],
            unsafeNames: []
        )

        viewModel.showImportResults(results)

        XCTAssertFalse(viewModel.isVaultImported)
        XCTAssertTrue(viewModel.showAlert)
        XCTAssertEqual(viewModel.alertTitle, "vaultRestoreFailed")
    }

    func testShowImportResultsNamesTheVaultsItRefusedToStore() {
        let results: EncryptedBackupViewModel.ImportResults = (
            imported: [],
            duplicates: 0,
            skippedNames: [],
            unsafeNames: ["Broken Vault"]
        )

        viewModel.showImportResults(results)

        XCTAssertFalse(viewModel.isVaultImported)
        XCTAssertTrue(viewModel.showAlert)
        XCTAssertTrue(
            viewModel.alertTitle.contains("Broken Vault"),
            "A refused vault must be named, not folded into the duplicate count"
        )
    }

    // MARK: - End-to-end against a real store

    func testZipImportRenamesInsteadOfOverwritingAStoredVault() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let context = token.container.mainContext

        let stored = makeVault(name: "Savings", ecdsa: "zzstored-ecdsa", eddsa: "zzstored-eddsa")
        stored.keyshares = [KeyShare(pubkey: "zzstored-ecdsa", keyshare: "stored-share")]
        context.insert(stored)

        let incoming = makeVault(name: "Savings", ecdsa: "zzincoming-ecdsa", eddsa: "zzincoming-eddsa")
        incoming.keyshares = [KeyShare(pubkey: "zzincoming-ecdsa", keyshare: "incoming-share")]
        givePlaceholderCoin(to: incoming)

        viewModel.multipleVaultsToImport = [incoming]
        viewModel.restoreMultipleVaults(modelContext: context, vaults: [stored])

        // Save so the unique indexes are actually applied by the store, not
        // just reasoned about in memory.
        try context.save()
        let all = try context.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(all.count, 2, "A name-only collision must not replace the stored vault")
        XCTAssertEqual(Set(all.map(\.name)), ["Savings", "Savings (2)"])

        let survivor = try XCTUnwrap(all.first { $0.pubKeyECDSA == "zzstored-ecdsa" })
        XCTAssertEqual(survivor.keyshares.map(\.keyshare), ["stored-share"], "The stored vault's key shares must survive")
        XCTAssertTrue(viewModel.isVaultImported)
    }

    func testZipImportSkipsAVaultThatSharesOnlyOnePublicKey() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let context = token.container.mainContext

        let stored = makeVault(name: "Savings", ecdsa: "zzshared-ecdsa", eddsa: "zzstored-eddsa")
        stored.keyshares = [KeyShare(pubkey: "zzshared-ecdsa", keyshare: "stored-share")]
        context.insert(stored)

        let incoming = makeVault(name: "Holidays", ecdsa: "zzshared-ecdsa", eddsa: "zzincoming-eddsa")
        givePlaceholderCoin(to: incoming)

        viewModel.multipleVaultsToImport = [incoming]
        viewModel.restoreMultipleVaults(modelContext: context, vaults: [stored])

        // Save so the unique indexes are actually applied by the store, not
        // just reasoned about in memory.
        try context.save()
        let all = try context.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(all.count, 1, "A partial key collision must be skipped, not upserted")
        XCTAssertEqual(all.first?.keyshares.map(\.keyshare), ["stored-share"])
        XCTAssertFalse(viewModel.isVaultImported)
    }

    func testZipImportDisambiguatesTwoIncomingVaultsSharingAName() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let context = token.container.mainContext

        let first = makeVault(name: "Savings", ecdsa: "zzfirst-ecdsa", eddsa: "zzfirst-eddsa")
        let second = makeVault(name: "Savings", ecdsa: "zzsecond-ecdsa", eddsa: "zzsecond-eddsa")
        givePlaceholderCoin(to: first)
        givePlaceholderCoin(to: second)

        viewModel.multipleVaultsToImport = [first, second]
        viewModel.restoreMultipleVaults(modelContext: context, vaults: [])

        // Save so the unique indexes are actually applied by the store, not
        // just reasoned about in memory.
        try context.save()
        let all = try context.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(all.count, 2, "Two same-named vaults in one batch must both land")
        XCTAssertEqual(Set(all.map(\.name)), ["Savings", "Savings (2)"])
    }

    // The three single-vault entry points share `insertIfSafe` with the zip
    // batch, but each is its own fund-safety call site — an accidental bypass in
    // any of them would compile and pass a suite that only drove the batch path.

    func testBakRestoreRenamesInsteadOfOverwritingAStoredVault() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let context = token.container.mainContext

        let stored = storeVault(named: "Savings", key: "zzstored", in: context)

        let incoming = makeVault(name: "Savings", ecdsa: "zzincoming-ecdsa", eddsa: "zzincoming-eddsa")
        let vaultData = try incoming.mapToProtobuff().serializedData()

        viewModel.restoreVaultBack(modelContext: context, vaults: [stored], vaultData: vaultData)

        try context.save()
        let all = try context.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(Set(all.map(\.name)), ["Savings", "Savings (2)"])
        XCTAssertEqual(survivingKeyshares(in: all), ["stored-share"])
        XCTAssertTrue(viewModel.isVaultImported)
    }

    func testJsonRestoreSkipsAVaultSharingOnlyOnePublicKey() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let context = token.container.mainContext

        let stored = storeVault(named: "Savings", key: "zzstored", in: context)

        let incoming = makeVault(name: "Holidays", ecdsa: "zzstored-ecdsa", eddsa: "zzincoming-eddsa")
        let backup = BackupVault(version: .v1, vault: incoming)
        viewModel.decryptedContent = try JSONEncoder().encode(backup).hexString

        viewModel.restoreVault(modelContext: context, vaults: [stored])

        try context.save()
        let all = try context.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(all.count, 1, "A partial key collision must be skipped, not upserted")
        XCTAssertEqual(survivingKeyshares(in: all), ["stored-share"])
        XCTAssertFalse(viewModel.isVaultImported)
        XCTAssertEqual(viewModel.alertTitle, "vaultAlreadyExists")
    }

    func testLegacyJsonRestoreRenamesInsteadOfOverwritingAStoredVault() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let context = token.container.mainContext

        let stored = storeVault(named: "Savings", key: "zzstored", in: context)

        // A bare `Vault` payload has no `version` key, so the new-format decode
        // fails and the legacy fallback branch handles it.
        let incoming = makeVault(name: "Savings", ecdsa: "zzincoming-ecdsa", eddsa: "zzincoming-eddsa")
        viewModel.decryptedContent = try JSONEncoder().encode(incoming).hexString

        viewModel.restoreVault(modelContext: context, vaults: [stored])

        try context.save()
        let all = try context.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(Set(all.map(\.name)), ["Savings", "Savings (2)"])
        XCTAssertEqual(survivingKeyshares(in: all), ["stored-share"])
        XCTAssertTrue(viewModel.isVaultImported)
    }

    // MARK: - Helpers

    private func makeVault(name: String, ecdsa: String, eddsa: String, mldsa: String? = nil) -> Vault {
        let vault = Vault(name: name)
        vault.pubKeyECDSA = ecdsa
        vault.pubKeyEdDSA = eddsa
        vault.publicKeyMLDSA44 = mldsa
        return vault
    }

    /// A stored vault holding one key share, so a test can assert the share
    /// survived rather than being upserted away with its owner.
    private func storeVault(named name: String, key: String, in context: ModelContext) -> Vault {
        let vault = makeVault(name: name, ecdsa: "\(key)-ecdsa", eddsa: "\(key)-eddsa")
        vault.keyshares = [KeyShare(pubkey: "\(key)-ecdsa", keyshare: "stored-share")]
        context.insert(vault)
        return vault
    }

    private func survivingKeyshares(in vaults: [Vault]) -> [String] {
        vaults.flatMap { $0.keyshares.map(\.keyshare) }.filter { $0 == "stored-share" }
    }

    /// `VaultDefaultCoinService` only derives default coins for a vault with no
    /// coins, and that derivation reaches for the network. A placeholder coin
    /// keeps these tests to the code under test.
    private func givePlaceholderCoin(to vault: Vault) {
        vault.coins = [
            Coin(
                asset: .make(chain: .bitcoin, ticker: "BTC"),
                address: "placeholder-\(vault.pubKeyECDSA)",
                hexPublicKey: vault.pubKeyECDSA
            )
        ]
    }
}
