//
//  VaultBackupExportTests.swift
//  VultisigAppTests
//

import CryptoKit
import VultisigCommonData
import XCTest
@testable import VultisigApp

/// Pins the one property the whole recovery design leans on: **`.vult` export
/// opens every share, or it throws.**
///
/// A device whose key shares are sealed with a key it no longer holds is told to
/// restore from its `.vult`. That advice is only true while the backups people
/// already hold are real backups — and the way this stops being true is quiet.
/// An export that skipped a share it could not open, or wrote the ciphertext
/// instead, produces a file that has the right name, the right size, imports
/// without complaint, and restores to a vault that cannot sign. Nothing on
/// either side reports anything.
///
/// These are **pins, not fail-first regressions.** `Vault.mapToProtobuff` is
/// already correct; the point is that it stays that way, so each test names the
/// specific plausible edit it would fail against rather than a bug that exists.
/// ``KeyshareAccessorTests`` covers the round trip and the locked case; what is
/// here is the granularity that survives a refactor — partial failure, and every
/// share rather than the first one.
final class VaultBackupExportTests: XCTestCase {

    private let shares = [
        ("02aaa", "eyJrZXlzaGFyZSI6ImVjZHNhIn0="),
        ("03bbb", #"{"PubKey":"03bbb","ShareID":{"value":"9"}}"#),
        ("04ccc", #"{"PubKey":"04ccc","ShareID":{"value":"11"}}"#)
    ]

    /// One key, made once. A closure that minted a fresh key on every `state()`
    /// read would seal and open under different keys and fail for a reason that
    /// has nothing to do with what is being pinned.
    private func makeUnlockedProtector() throws -> KeyshareProtector {
        let key = try VaultCryptoEnvelope.randomKey()
        return KeyshareProtector(state: { .unlocked(key) })
    }

    private func makeVault(keyshares: [KeyShare]) -> Vault {
        let vault = Vault(name: "Test Vault")
        vault.pubKeyECDSA = shares[0].0
        vault.pubKeyEdDSA = shares[1].0
        vault.hexChainCode = "abcd"
        vault.localPartyID = "iPhone-1"
        vault.signers = ["iPhone-1", "iPad-2"]
        vault.libType = .DKLS
        vault.keyshares = keyshares
        return vault
    }

    /// Every share reaches the file, in the clear, with its own public key.
    ///
    /// The edit this fails against is any rewrite that opens the first share and
    /// reuses the result, or that maps over a subset — both of which produce a
    /// file that passes a "does it contain plaintext?" check on its first entry.
    func testExportOpensEveryShareRatherThanOnlyTheFirst() throws {
        let protector = try makeUnlockedProtector()
        let vault = makeVault(
            keyshares: try shares.map {
                try KeyShare.sealed(pubkey: $0.0, keyshare: $0.1, protector: protector)
            }
        )

        let proto = try vault.mapToProtobuff(protector: protector)

        XCTAssertEqual(proto.keyShares.count, shares.count)
        for (index, expected) in shares.enumerated() {
            XCTAssertEqual(proto.keyShares[index].publicKey, expected.0)
            XCTAssertEqual(proto.keyShares[index].keyshare, expected.1)
        }
    }

    /// A share sealed under a key this device does not hold is exactly the
    /// orphaned state, and the export has to refuse rather than write the
    /// envelope it cannot open.
    func testExportThrowsRatherThanWritingAShareItCannotOpen() throws {
        let sealing = try makeUnlockedProtector()
        let vault = makeVault(
            keyshares: try shares.map {
                try KeyShare.sealed(pubkey: $0.0, keyshare: $0.1, protector: sealing)
            }
        )

        // A different data key — the same thing a restore onto another device
        // produces, and the one case where a silently-written backup would be
        // ciphertext nobody can ever open.
        let otherDevice = try makeUnlockedProtector()

        XCTAssertThrowsError(try vault.mapToProtobuff(protector: otherDevice)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .cipherFailure)
        }
    }

    /// The partial case, and the one a `try?` or a `compactMap` would turn into
    /// a backup that looks complete.
    ///
    /// Plaintext passes through `open` in every state, so a vault part-way
    /// through a sweep exports its readable shares perfectly well. One share it
    /// cannot open has to take the whole export down with it — a `.vult` missing
    /// a share restores to a vault that cannot sign, and says nothing.
    func testOneUnopenableShareRefusesTheWholeExport() throws {
        let sealing = try makeUnlockedProtector()
        let vault = makeVault(
            keyshares: [
                KeyShare(pubkey: shares[0].0, keyshare: shares[0].1),
                try KeyShare.sealed(pubkey: shares[1].0, keyshare: shares[1].1, protector: sealing),
                KeyShare(pubkey: shares[2].0, keyshare: shares[2].1)
            ]
        )

        let locked = KeyshareProtector(state: { .locked })

        // Precondition, so the assertion below cannot pass because nothing was
        // readable: the two plaintext shares open under the same locked
        // protector that refuses the sealed one.
        XCTAssertEqual(try locked.open(shares[0].1), shares[0].1)
        XCTAssertEqual(try locked.open(shares[2].1), shares[2].1)

        XCTAssertThrowsError(try vault.mapToProtobuff(protector: locked)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
    }

    /// And the same rule with nothing sealed at all: a vault with no passcode
    /// exports byte-for-byte, which is the acceptance test this feature is held
    /// to for every user who never turns a passcode on.
    func testAVaultWithNoPasscodeExportsItsSharesUnchanged() throws {
        let disabled = KeyshareProtector(state: { .disabled })
        let vault = makeVault(
            keyshares: shares.map { KeyShare(pubkey: $0.0, keyshare: $0.1) }
        )

        let proto = try vault.mapToProtobuff(protector: disabled)

        XCTAssertEqual(proto.keyShares.map(\.keyshare), shares.map(\.1))
    }
}
