//
//  KeyshareAccessorTests.swift
//  VultisigAppTests
//

import CryptoKit
import VultisigCommonData
import XCTest
@testable import VultisigApp

/// Pins the two properties this step is claiming.
///
/// One: with protection disabled — the state every install with no passcode set
/// is in, permanently — reading and writing a share is byte-for-byte what it was
/// before the accessor existed.
///
/// Two: a `.vult` backup survives a round trip with shares sealed. Getting that
/// wrong is the quiet failure in this whole feature: export forgetting to open a
/// share produces a file that looks like a backup, imports without complaint,
/// and restores to a vault that cannot sign.
final class KeyshareAccessorTests: XCTestCase {

    private let ecdsaPubKey = "02aaa"
    private let eddsaPubKey = "03bbb"
    private let ecdsaShare = "eyJrZXlzaGFyZSI6ImVjZHNhIn0="
    private let eddsaShare = #"{"PubKey":"03bbb","ShareID":{"value":"9"}}"#

    private func makeUnlockedProtector() throws -> KeyshareProtector {
        let key = try VaultCryptoEnvelope.randomKey()
        return KeyshareProtector(state: { .unlocked(key) })
    }

    private func makeVault(protector: KeyshareProtecting) throws -> Vault {
        let vault = Vault(name: "Test Vault")
        vault.pubKeyECDSA = ecdsaPubKey
        vault.pubKeyEdDSA = eddsaPubKey
        vault.hexChainCode = "abcd"
        vault.localPartyID = "iPhone-1"
        vault.signers = ["iPhone-1", "iPad-2"]
        vault.libType = .DKLS
        vault.keyshares = [
            try KeyShare.sealed(pubkey: ecdsaPubKey, keyshare: ecdsaShare, protector: protector),
            try KeyShare.sealed(pubkey: eddsaPubKey, keyshare: eddsaShare, protector: protector)
        ]
        return vault
    }

    // MARK: - Disabled: the accessor is a no-op

    func testDisabledStoresSharesAsPlaintext() throws {
        let protector = KeyshareProtector(state: { .disabled })

        let vault = try makeVault(protector: protector)

        XCTAssertEqual(vault.keyshares[0].keyshare, ecdsaShare, "Nothing should be sealed while no passcode is set")
        XCTAssertEqual(vault.keyshares[1].keyshare, eddsaShare)
    }

    func testDisabledReadsShareBack() throws {
        let protector = KeyshareProtector(state: { .disabled })
        let vault = try makeVault(protector: protector)

        XCTAssertEqual(try vault.keyshareValue(for: ecdsaPubKey, protector: protector), ecdsaShare)
        XCTAssertEqual(try vault.keyshareValue(for: eddsaPubKey, protector: protector), eddsaShare)
    }

    func testUnknownPubKeyReturnsNil() throws {
        let protector = KeyshareProtector(state: { .disabled })
        let vault = try makeVault(protector: protector)

        XCTAssertNil(try vault.keyshareValue(for: "not-a-key", protector: protector))
        XCTAssertNil(vault.getKeyshare(pubKey: "not-a-key"))
    }

    // MARK: - Sealed: the read path opens

    func testSealedSharesAreStoredAsCiphertextAndReadBackAsPlaintext() throws {
        let protector = try makeUnlockedProtector()
        let vault = try makeVault(protector: protector)

        XCTAssertNotEqual(vault.keyshares[0].keyshare, ecdsaShare)
        XCTAssertTrue(vault.keyshares[0].keyshare.hasPrefix(AesGcmKeyshareCipher.sealedPrefix))

        XCTAssertEqual(try vault.keyshareValue(for: ecdsaPubKey, protector: protector), ecdsaShare)
        XCTAssertEqual(try vault.keyshareValue(for: eddsaPubKey, protector: protector), eddsaShare)
    }

    func testReadingASealedShareWhileLockedThrows() throws {
        let unlocked = try makeUnlockedProtector()
        let vault = try makeVault(protector: unlocked)
        let locked = KeyshareProtector(state: { .locked })

        XCTAssertThrowsError(try vault.keyshareValue(for: ecdsaPubKey, protector: locked)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
    }

    // MARK: - .vult backup round trip

    func testBackupRoundTripPreservesSharesWhenDisabled() throws {
        let protector = KeyshareProtector(state: { .disabled })
        let vault = try makeVault(protector: protector)

        let proto = try vault.mapToProtobuff(protector: protector)
        let restored = try Vault(proto: proto, protector: protector)

        XCTAssertEqual(try restored.keyshareValue(for: ecdsaPubKey, protector: protector), ecdsaShare)
        XCTAssertEqual(try restored.keyshareValue(for: eddsaPubKey, protector: protector), eddsaShare)
    }

    /// Export must open before writing, or the backup carries ciphertext.
    func testBackupExportWritesPlaintextSharesNotCiphertext() throws {
        let protector = try makeUnlockedProtector()
        let vault = try makeVault(protector: protector)

        let proto = try vault.mapToProtobuff(protector: protector)

        let exported = proto.keyShares.map(\.keyshare)
        XCTAssertEqual(Set(exported), Set([ecdsaShare, eddsaShare]))
        for share in exported {
            XCTAssertFalse(share.hasPrefix(AesGcmKeyshareCipher.sealedPrefix), "A backup must never contain ciphertext")
        }
    }

    /// A backup taken on one device must restore on another, whose data key is
    /// necessarily different.
    func testBackupRestoresUnderADifferentDataKey() throws {
        let exporting = try makeUnlockedProtector()
        let importing = try makeUnlockedProtector()
        let vault = try makeVault(protector: exporting)

        let proto = try vault.mapToProtobuff(protector: exporting)
        let restored = try Vault(proto: proto, protector: importing)

        XCTAssertTrue(restored.keyshares[0].keyshare.hasPrefix(AesGcmKeyshareCipher.sealedPrefix))
        XCTAssertEqual(try restored.keyshareValue(for: ecdsaPubKey, protector: importing), ecdsaShare)
        XCTAssertEqual(try restored.keyshareValue(for: eddsaPubKey, protector: importing), eddsaShare)
    }

    func testBackupExportWhileLockedThrowsRatherThanWritingCiphertext() throws {
        let unlocked = try makeUnlockedProtector()
        let vault = try makeVault(protector: unlocked)
        let locked = KeyshareProtector(state: { .locked })

        XCTAssertThrowsError(try vault.mapToProtobuff(protector: locked)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
    }
}
