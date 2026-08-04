//
//  ProtectedVaultImporterTests.swift
//  VultisigAppTests
//

import CryptoKit
import SwiftData
import XCTest
@testable import VultisigApp

/// The hole this closes was silent by construction: `Vault.init(from: Decoder)`
/// decodes `[KeyShare]` straight off the wire, so a JSON import with a passcode
/// set stored plaintext shares in a protected store and nothing ever complained.
@MainActor
final class ProtectedVaultImporterTests: XCTestCase {

    private var token: TestContextToken!
    private var context: ModelContext!
    private var key: SymmetricKey!
    private var coordinator: KeyshareWriteCoordinator!

    private let firstShare = "eyJrZXlzaGFyZSI6ImRrbHMtb25lIn0="
    private let secondShare = "eyJrZXlzaGFyZSI6ImRrbHMtdHdvIn0="

    override func setUpWithError() throws {
        try super.setUpWithError()
        token = try TestStore.installInMemoryContainer()
        context = token.container.mainContext
        key = SymmetricKey(size: .bits256)
        coordinator = KeyshareWriteCoordinator()
    }

    override func tearDown() {
        coordinator = nil
        key = nil
        context = nil
        TestStore.restore(token)
        token = nil
        super.tearDown()
    }

    // MARK: - Normalizing under the current state

    /// The bug, asserted. A legacy JSON backup carries plaintext shares; with a
    /// passcode set they must not reach disk that way.
    func testAPlaintextImportIsSealedWhenAPasscodeIsSet() throws {
        let sut = makeImporter(state: .unlocked(key))
        let vault = makeVault(shares: [firstShare, secondShare])

        try sut.commit([vault], into: context)

        let protector = KeyshareProtector(state: { [key] in .unlocked(key!) })
        let stored = try storedShares()
        XCTAssertEqual(stored.count, 2)
        for value in stored {
            XCTAssertTrue(protector.isSealed(value), "an imported share must land on the same side of the invariant as the store")
        }
        XCTAssertEqual(try stored.map { try protector.open($0) }.sorted(), [firstShare, secondShare].sorted())
    }

    /// And the other half of the acceptance test: with no passcode, the stored
    /// bytes are byte-identical to what a build without this feature writes.
    func testAPlaintextImportStaysByteIdenticalWithNoPasscodeSet() throws {
        let sut = makeImporter(state: .disabled)
        let vault = makeVault(shares: [firstShare, secondShare])

        try sut.commit([vault], into: context)

        XCTAssertEqual(try storedShares(), [firstShare, secondShare])
    }

    /// A `.vult` exported from a sealed store legitimately carries `vlt2:`
    /// values. With the same key in hand they open, and the import is accepted.
    func testAnAlreadySealedImportIsAcceptedWhenItAuthenticates() throws {
        let sealed = try AesGcmKeyshareCipher().seal(firstShare, with: key)
        let sut = makeImporter(state: .unlocked(key))

        try sut.commit([makeVault(shares: [sealed])], into: context)

        let protector = KeyshareProtector(state: { [key] in .unlocked(key!) })
        XCTAssertEqual(try protector.open(try XCTUnwrap(try storedShares().first)), firstShare)
    }

    /// With no passcode set the same value is refused rather than stored: there
    /// is no key to open it with, so importing it would store a share nobody can
    /// ever read while reporting success.
    func testAnAlreadySealedImportIsRefusedWithNoPasscodeSet() throws {
        let sealed = try AesGcmKeyshareCipher().seal(firstShare, with: key)
        let sut = makeImporter(state: .disabled)

        XCTAssertThrowsError(try sut.commit([makeVault(shares: [sealed])], into: context)) { error in
            XCTAssertEqual(error as? ProtectedVaultImportError, .unreadableShare(pubkey: "vault-one-0"))
        }
        XCTAssertEqual(try storedShares(), [])
    }

    // MARK: - Authenticating what comes in

    /// The rule that makes the import a boundary rather than a funnel: a sealed
    /// value from another device authenticates against nothing here, and storing
    /// it would import a share nobody can open.
    func testAShareSealedUnderAnotherKeyIsRefused() throws {
        let foreign = try AesGcmKeyshareCipher().seal(firstShare, with: SymmetricKey(size: .bits256))
        let sut = makeImporter(state: .unlocked(key))

        XCTAssertThrowsError(try sut.commit([makeVault(shares: [foreign])], into: context)) { error in
            XCTAssertEqual(error as? ProtectedVaultImportError, .unreadableShare(pubkey: "vault-one-0"))
        }
        XCTAssertEqual(try storedShares(), [])
    }

    /// An envelope wrapped around another envelope is not a share, and the outer
    /// layer authenticates perfectly well — so accepting it on that basis is
    /// exactly the mistake the check exists to stop.
    func testAnEnvelopeWrappedAroundAnotherEnvelopeIsRefused() throws {
        let cipher = AesGcmKeyshareCipher()
        let nested = try cipher.seal(try cipher.seal(firstShare, with: key), with: key)
        let sut = makeImporter(state: .unlocked(key))

        XCTAssertThrowsError(try sut.commit([makeVault(shares: [nested])], into: context)) { error in
            XCTAssertEqual(error as? ProtectedVaultImportError, .unreadableShare(pubkey: "vault-one-0"))
        }
    }

    func testValidateRefusesABackupTheDeviceCannotOpen() throws {
        let foreign = try AesGcmKeyshareCipher().seal(firstShare, with: SymmetricKey(size: .bits256))
        let sut = makeImporter(state: .unlocked(key))

        XCTAssertThrowsError(try sut.validate(makeVault(shares: [foreign]))) { error in
            XCTAssertEqual(error as? ProtectedVaultImportError, .unreadableShare(pubkey: "vault-one-0"))
        }
    }

    func testValidateAcceptsAPlaintextBackup() throws {
        let sut = makeImporter(state: .unlocked(key))

        XCTAssertNoThrow(try sut.validate(makeVault(shares: [firstShare])))
    }

    // MARK: - The commit itself

    /// Two phases: one bad share anywhere means nothing is inserted, so a ZIP
    /// whose third file is corrupt does not leave the first two half-imported.
    func testABadShareInOneVaultImportsNoneOfThem() throws {
        let foreign = try AesGcmKeyshareCipher().seal(firstShare, with: SymmetricKey(size: .bits256))
        let sut = makeImporter(state: .unlocked(key))
        let good = makeVault(name: "vault-one", shares: [firstShare])
        let bad = makeVault(name: "vault-two", shares: [foreign])

        XCTAssertThrowsError(try sut.commit([good, bad], into: context))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Vault>()), 0)
    }

    /// The insert is saved explicitly rather than left to an autosave that could
    /// land after a passcode transition has begun. Read back through a context
    /// that never saw the in-memory objects.
    func testTheImportIsSavedRatherThanLeftToAnAutosave() throws {
        let sut = makeImporter(state: .unlocked(key))

        try sut.commit([makeVault(shares: [firstShare])], into: context)

        let fresh = ModelContext(token.container)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Vault>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    /// A transition is about to rewrite every stored share, and a vault inserted
    /// underneath it would never be swept — plaintext behind a live passcode.
    func testAnImportIsRefusedWhileAPasscodeTransitionIsHeld() throws {
        let sut = makeImporter(state: .unlocked(key))
        let lease = try coordinator.beginTransition()
        defer { coordinator.end(lease) }

        XCTAssertThrowsError(try sut.commit([makeVault(shares: [firstShare])], into: context)) { error in
            XCTAssertEqual(error as? ProtectedVaultImportError, .busy)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Vault>()), 0)
    }

    /// A locked app has no key to normalize with, and `seal` says so rather than
    /// quietly storing plaintext.
    func testAnImportIsRefusedWhileTheAppIsLocked() throws {
        let sut = makeImporter(state: .locked)

        XCTAssertThrowsError(try sut.commit([makeVault(shares: [firstShare])], into: context)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Vault>()), 0)
    }

    /// `keyId` is part of a share's identity for MLDSA, and rebuilding the array
    /// is exactly where it would get dropped.
    func testTheImportPreservesTheKeyIdentifier() throws {
        let sut = makeImporter(state: .unlocked(key))
        let vault = makeVault(shares: [])
        vault.keyshares = [KeyShare(pubkey: "vault-one-0", keyshare: firstShare, keyId: "mldsa-key-id")]

        try sut.commit([vault], into: context)

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Vault>()).flatMap(\.keyshares).first)
        XCTAssertEqual(stored.keyId, "mldsa-key-id")
    }

    // MARK: - Helpers

    private func makeImporter(state: KeyshareProtectionState) -> ProtectedVaultImporter {
        ProtectedVaultImporter(
            protector: KeyshareProtector(state: { state }),
            coordinator: coordinator
        )
    }

    /// Built directly rather than through `TestStore.makeVault`, which leaves
    /// `pubKeyEdDSA` at a shared constant — SwiftData answers a duplicate
    /// `@Attribute(.unique)` with an upsert rather than an error, so a
    /// multi-vault fixture built that way collapses to one row.
    private func makeVault(name: String = "vault-one", shares: [String]) -> Vault {
        Vault(
            name: "Vault \(name)",
            signers: [],
            pubKeyECDSA: "ecdsa-\(name)",
            pubKeyEdDSA: "eddsa-\(name)",
            keyshares: shares.enumerated().map { index, value in
                KeyShare(pubkey: "\(name)-\(index)", keyshare: value)
            },
            localPartyID: "party-\(name)",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func storedShares() throws -> [String] {
        try context.fetch(FetchDescriptor<Vault>()).flatMap(\.keyshares).map(\.keyshare)
    }
}
