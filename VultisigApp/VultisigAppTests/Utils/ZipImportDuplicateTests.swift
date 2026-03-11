//
//  ZipImportDuplicateTests.swift
//  VultisigAppTests
//
//  Tests for duplicate vault handling during .zip import (issue #3982)
//

import XCTest
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

    func testIsVaultUnique_withPartialKeyMatch_returnsTrue() {
        let existing = makeVault(name: "Vault A", ecdsa: "key1", eddsa: "key2")
        // Same ECDSA but different EdDSA — should be treated as unique
        let partial = makeVault(name: "Vault B", ecdsa: "key1", eddsa: "key999")
        XCTAssertTrue(viewModel.isVaultUnique(backupVault: partial, vaults: [existing]))
    }

    // MARK: - showImportResults

    func testShowImportResults_allNew_setsImportedSuccessfully() {
        let vault = makeVault(name: "Vault A", ecdsa: "k1", eddsa: "k2")
        let results: (imported: [Vault], duplicates: Int, skippedNames: [String]) = (
            imported: [vault],
            duplicates: 0,
            skippedNames: []
        )

        viewModel.showImportResults(results)

        XCTAssertTrue(viewModel.isVaultImported)
        XCTAssertFalse(viewModel.showAlert)
        XCTAssertEqual(viewModel.alertTitle, "vaultImportedSuccessfully")
    }

    func testShowImportResults_multipleAllNew_setsVaultsImportedSuccessfully() {
        let v1 = makeVault(name: "V1", ecdsa: "k1", eddsa: "k2")
        let v2 = makeVault(name: "V2", ecdsa: "k3", eddsa: "k4")
        let results: (imported: [Vault], duplicates: Int, skippedNames: [String]) = (
            imported: [v1, v2],
            duplicates: 0,
            skippedNames: []
        )

        viewModel.showImportResults(results)

        XCTAssertTrue(viewModel.isVaultImported)
        XCTAssertFalse(viewModel.showAlert)
        XCTAssertEqual(viewModel.alertTitle, "vaultsImportedSuccessfully")
    }

    func testShowImportResults_mixed_showsPartialSuccess() {
        let imported = makeVault(name: "New Vault", ecdsa: "k1", eddsa: "k2")
        let results: (imported: [Vault], duplicates: Int, skippedNames: [String]) = (
            imported: [imported],
            duplicates: 1,
            skippedNames: ["Old Vault"]
        )

        viewModel.showImportResults(results)

        XCTAssertTrue(viewModel.isVaultImported, "Should still mark as imported when some vaults succeeded")
        XCTAssertTrue(viewModel.showAlert, "Should show alert with details about skipped vaults")
        XCTAssertTrue(viewModel.alertTitle.contains("Old Vault"), "Alert should mention the skipped vault name")
    }

    func testShowImportResults_allDuplicates_showsInfoNotError() {
        let results: (imported: [Vault], duplicates: Int, skippedNames: [String]) = (
            imported: [],
            duplicates: 2,
            skippedNames: ["Vault A", "Vault B"]
        )

        viewModel.showImportResults(results)

        XCTAssertFalse(viewModel.isVaultImported, "Should not mark as imported when all are duplicates")
        XCTAssertTrue(viewModel.showAlert, "Should show informational alert")
        XCTAssertTrue(viewModel.alertTitle.contains("Vault A"), "Alert should list skipped vault names")
        XCTAssertTrue(viewModel.alertTitle.contains("Vault B"), "Alert should list skipped vault names")
    }

    func testShowImportResults_noneImportedNoDuplicates_showsRestoreFailed() {
        let results: (imported: [Vault], duplicates: Int, skippedNames: [String]) = (
            imported: [],
            duplicates: 0,
            skippedNames: []
        )

        viewModel.showImportResults(results)

        XCTAssertFalse(viewModel.isVaultImported)
        XCTAssertTrue(viewModel.showAlert)
        XCTAssertEqual(viewModel.alertTitle, "vaultRestoreFailed")
    }

    // MARK: - Helpers

    private func makeVault(name: String, ecdsa: String, eddsa: String) -> Vault {
        let vault = Vault(name: name)
        vault.pubKeyECDSA = ecdsa
        vault.pubKeyEdDSA = eddsa
        return vault
    }
}
