//
//  BackupImportProtectionTests.swift
//  VultisigAppTests
//

import CryptoKit
import SwiftData
import XCTest
@testable import VultisigApp

/// Routing, end to end through `EncryptedBackupViewModel`.
///
/// `ProtectedVaultImporterTests` pins what the importer does; these pin that the
/// import *paths* actually reach it. That distinction is the whole bug: the
/// importer's rules were already true of the protobuf path, and the JSON paths
/// simply never went near it.
@MainActor
final class BackupImportProtectionTests: XCTestCase {

    private var token: TestContextToken!
    private var context: ModelContext!
    private var key: SymmetricKey!

    private let share = "eyJrZXlzaGFyZSI6ImRrbHMifQ=="

    override func setUpWithError() throws {
        try super.setUpWithError()
        token = try TestStore.installInMemoryContainer()
        context = token.container.mainContext
        key = SymmetricKey(size: .bits256)
    }

    override func tearDown() {
        key = nil
        context = nil
        TestStore.restore(token)
        token = nil
        super.tearDown()
    }

    /// The bug this closes, through the real code path: a `BackupVault` JSON
    /// import used to store its shares exactly as decoded, so with a passcode
    /// set the store ended up holding plaintext behind a lock screen.
    func testALegacyJsonImportIsSealedWhenAPasscodeIsSet() throws {
        let sut = makeViewModel(state: .unlocked(key))
        sut.decryptedContent = try backupVaultJSONHex()

        sut.restoreVault(modelContext: context, vaults: [])

        XCTAssertTrue(sut.isVaultImported)
        let protector = KeyshareProtector(state: { [key] in .unlocked(key!) })
        let stored = try XCTUnwrap(try storedShares().first)
        XCTAssertTrue(protector.isSealed(stored), "a JSON import must not put plaintext behind a passcode")
        XCTAssertEqual(try protector.open(stored), share)
    }

    /// The acceptance test on the same path: with no passcode the stored bytes
    /// are exactly what the backup carried.
    func testTheSameImportStaysByteIdenticalWithNoPasscodeSet() throws {
        let sut = makeViewModel(state: .disabled)
        sut.decryptedContent = try backupVaultJSONHex()

        sut.restoreVault(modelContext: context, vaults: [])

        XCTAssertTrue(sut.isVaultImported)
        XCTAssertEqual(try storedShares(), [share])
    }

    /// The bare-`Vault` fallback is a separate decode with its own store, and it
    /// used to have its own copy of the bypass.
    func testTheOldFormatFallbackIsAlsoProtected() throws {
        let sut = makeViewModel(state: .unlocked(key))
        sut.decryptedContent = try JSONEncoder().encode(makeVault()).hexString

        sut.restoreVault(modelContext: context, vaults: [])

        XCTAssertTrue(sut.isVaultImported)
        let protector = KeyshareProtector(state: { [key] in .unlocked(key!) })
        XCTAssertTrue(protector.isSealed(try XCTUnwrap(try storedShares().first)))
    }

    /// A backup carrying a share this device cannot open is refused rather than
    /// stored, and the user is told the import failed.
    func testAnImportCarryingAnUnopenableShareIsRefused() throws {
        let foreign = try AesGcmKeyshareCipher().seal(share, with: SymmetricKey(size: .bits256))
        let sut = makeViewModel(state: .unlocked(key))
        sut.decryptedContent = try backupVaultJSONHex(shareValue: foreign)

        sut.restoreVault(modelContext: context, vaults: [])

        XCTAssertFalse(sut.isVaultImported)
        XCTAssertEqual(sut.alertTitle, "vaultRestoreFailed")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Vault>()), 0)
    }

    /// And nothing of the import survives the refusal — including the default
    /// coins, which insert rows of their own.
    func testARefusedImportLeavesNothingInTheStore() throws {
        let foreign = try AesGcmKeyshareCipher().seal(share, with: SymmetricKey(size: .bits256))
        let sut = makeViewModel(state: .unlocked(key))
        sut.decryptedContent = try backupVaultJSONHex(shareValue: foreign)

        sut.restoreVault(modelContext: context, vaults: [])

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Coin>()), 0, "default coins must not outlive a refused import")
    }

    // MARK: - Helpers

    private func makeViewModel(state: KeyshareProtectionState) -> EncryptedBackupViewModel {
        EncryptedBackupViewModel(
            importer: ProtectedVaultImporter(
                protector: KeyshareProtector(state: { state }),
                coordinator: KeyshareWriteCoordinator()
            )
        )
    }

    private func makeVault(shareValue: String? = nil) -> Vault {
        Vault(
            name: "Imported",
            signers: ["a", "b"],
            pubKeyECDSA: "ecdsa-imported",
            pubKeyEdDSA: "eddsa-imported",
            keyshares: [KeyShare(pubkey: "ecdsa-imported", keyshare: shareValue ?? share)],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func backupVaultJSONHex(shareValue: String? = nil) throws -> String {
        try JSONEncoder().encode(BackupVault(version: .v1, vault: makeVault(shareValue: shareValue))).hexString
    }

    private func storedShares() throws -> [String] {
        try context.fetch(FetchDescriptor<Vault>()).flatMap(\.keyshares).map(\.keyshare)
    }
}
