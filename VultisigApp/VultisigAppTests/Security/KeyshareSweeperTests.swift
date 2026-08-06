//
//  KeyshareSweeperTests.swift
//  VultisigAppTests
//

import CryptoKit
import SwiftData
import XCTest
@testable import VultisigApp

/// The sweep is the only thing in the passcode feature that rewrites key
/// material, so these are less about behaviour than about the four ways it could
/// destroy a vault: half-applying, failing to persist, saving a partial result,
/// and accepting an already-sealed value nobody can open.
@MainActor
final class KeyshareSweeperTests: XCTestCase {

    private var token: TestContextToken!
    private var context: ModelContext!
    private var key: SymmetricKey!
    private var protector: KeyshareProtector!
    private var sut: KeyshareSweeper!

    private let firstShare = "eyJrZXlzaGFyZSI6ImRrbHMtb25lIn0="
    private let secondShare = "eyJrZXlzaGFyZSI6ImRrbHMtdHdvIn0="
    private let thirdShare = "eyJrZXlzaGFyZSI6ImRrbHMtdGhyZWUifQ=="

    override func setUpWithError() throws {
        try super.setUpWithError()
        token = try TestStore.installInMemoryContainer()
        context = token.container.mainContext

        key = SymmetricKey(size: .bits256)
        let heldKey = key!
        protector = KeyshareProtector(state: { .unlocked(heldKey) })
        sut = KeyshareSweeper(protector: protector, context: { [context] in context })
    }

    override func tearDown() {
        sut = nil
        protector = nil
        key = nil
        context = nil
        TestStore.restore(token)
        token = nil
        super.tearDown()
    }

    // MARK: - Sealing

    func testSealAllSealsEveryShareOfEveryVault() throws {
        try givenVaults([
            ("vault-one", [firstShare, secondShare]),
            ("vault-two", [thirdShare])
        ])

        try sut.sealAll()

        let stored = try storedShares()
        XCTAssertEqual(stored.count, 3)
        for value in stored {
            XCTAssertTrue(protector.isSealed(value), "every share must be sealed once a passcode is set")
        }
        XCTAssertEqual(try stored.map { try protector.open($0) }.sorted(), [firstShare, secondShare, thirdShare].sorted())
    }

    func testSealAllPersistsThroughAFreshFetch() throws {
        try givenVaults([("vault-one", [firstShare])])

        try sut.sealAll()

        // Read through a context that never saw the in-memory objects. This is
        // the reason the sweep assigns a whole array rather than an element:
        // element assignment is not a dependable way to dirty a `@Model`, and a
        // change that never reached the store would leave plaintext on disk
        // while every in-process read looked correct.
        let fresh = ModelContext(token.container)
        let stored = try fresh.fetch(FetchDescriptor<Vault>()).flatMap(\.keyshares).map(\.keyshare)
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(protector.isSealed(try XCTUnwrap(stored.first)))
    }

    func testSealAllIsIdempotent() throws {
        try givenVaults([("vault-one", [firstShare, secondShare])])
        try sut.sealAll()
        let afterFirst = try storedShares()

        try sut.sealAll()

        XCTAssertEqual(try storedShares().sorted(), afterFirst.sorted(), "re-sealing must not re-encrypt")
    }

    func testSealAllOverAStoreWithNoVaultsDoesNothing() throws {
        try sut.sealAll()

        XCTAssertFalse(context.hasChanges)
    }

    /// Rule 4, and the one that costs funds. `KeyshareProtector.seal` returns an
    /// already-sealed value unchanged and unauthenticated, so a sweep that took
    /// it on trust would report success over a share sealed under a key nobody
    /// holds — a dead vault that nothing ever revisits, because the sweep said
    /// it was fine.
    func testAnAlreadySealedShareSealedUnderAnotherKeyAbortsTheSweep() throws {
        let foreign = try AesGcmKeyshareCipher().seal(firstShare, with: SymmetricKey(size: .bits256))
        try givenVaults([("vault-one", [foreign])])

        XCTAssertThrowsError(try sut.sealAll()) { error in
            XCTAssertEqual(error as? KeyshareSweeperError, .verificationFailed(pubkey: "vault-one-0"))
        }
    }

    /// A sealed envelope wrapped around another one is not a share. Nothing here
    /// produces one — `seal` will not seal an already-sealed value — but an
    /// imported backup can carry whatever bytes it likes, and the outer layer
    /// authenticates perfectly well, so accepting it on that basis is exactly
    /// the mistake rule 4 exists to stop.
    func testAnEnvelopeWrappedAroundAnotherEnvelopeAbortsTheSeal() throws {
        try givenVaults([("vault-one", [try nestedEnvelope()])])

        XCTAssertThrowsError(try sut.sealAll()) { error in
            XCTAssertEqual(error as? KeyshareSweeperError, .verificationFailed(pubkey: "vault-one-0"))
        }
    }

    /// The same value on the way out, where the consequence is worse: unwrapping
    /// only the outer layer would write `vlt2:` back to disk and report the
    /// store fully unsealed, and the disable that follows deletes the key.
    func testAnEnvelopeWrappedAroundAnotherEnvelopeAbortsTheUnseal() throws {
        let nested = try nestedEnvelope()
        try givenVaults([("vault-one", [nested])])

        XCTAssertThrowsError(try sut.unsealAll()) { error in
            XCTAssertEqual(error as? KeyshareSweeperError, .verificationFailed(pubkey: "vault-one-0"))
        }
        XCTAssertEqual(try storedShares(), [nested], "the refusal must leave the value alone")
    }

    /// Two-phase, proved: one bad share anywhere leaves every other share — in
    /// every other vault — exactly as it was, and leaves nothing dirty behind
    /// for an unrelated save to flush.
    func testAFailureAnywhereLeavesEveryShareUntouched() throws {
        let foreign = try AesGcmKeyshareCipher().seal(thirdShare, with: SymmetricKey(size: .bits256))
        try givenVaults([
            ("vault-one", [firstShare, secondShare]),
            ("vault-two", [foreign])
        ])

        XCTAssertThrowsError(try sut.sealAll())

        XCTAssertEqual(try storedShares().sorted(), [firstShare, secondShare, foreign].sorted())
        XCTAssertFalse(context.hasChanges, "a failed sweep must not leave a partial result in the context")
    }

    // MARK: - Unsealing

    func testUnsealAllRestoresTheExactOriginalPlaintext() throws {
        try givenVaults([
            ("vault-one", [firstShare, secondShare]),
            ("vault-two", [thirdShare])
        ])
        try sut.sealAll()

        try sut.unsealAll()

        XCTAssertEqual(try storedShares().sorted(), [firstShare, secondShare, thirdShare].sorted())
    }

    func testUnsealAllIsIdempotent() throws {
        try givenVaults([("vault-one", [firstShare])])
        try sut.sealAll()
        try sut.unsealAll()

        try sut.unsealAll()

        XCTAssertEqual(try storedShares(), [firstShare])
    }

    /// A sealed value that does not authenticate cannot be turned back into a
    /// share, and reporting the disable as done would leave it unreadable
    /// forever with no passcode left to ask for.
    func testUnsealAllAbortsOnAShareItCannotOpen() throws {
        let foreign = try AesGcmKeyshareCipher().seal(firstShare, with: SymmetricKey(size: .bits256))
        try givenVaults([("vault-one", [foreign])])

        XCTAssertThrowsError(try sut.unsealAll()) { error in
            XCTAssertEqual(error as? KeyshareSweeperError, .verificationFailed(pubkey: "vault-one-0"))
        }
        XCTAssertEqual(try storedShares(), [foreign])
    }

    // MARK: - The context

    /// Flushing somebody's pending work would commit a half-finished keygen
    /// merely because the user enabled a passcode; discarding it would throw
    /// their work away. Neither is the sweep's to do.
    func testADirtyContextIsRefusedAndNothingIsChanged() throws {
        let vaults = try givenVaults([("vault-one", [firstShare])])
        vaults[0].name = "renamed but not saved"
        XCTAssertTrue(context.hasChanges)

        XCTAssertThrowsError(try sut.sealAll()) { error in
            XCTAssertEqual(error as? KeyshareSweeperError, .busy)
        }

        XCTAssertEqual(try storedShares(), [firstShare], "the refusal must change nothing")
    }

    func testAMissingModelContextIsReported() {
        let orphan = KeyshareSweeper(protector: protector, context: { nil })

        XCTAssertThrowsError(try orphan.sealAll()) { error in
            XCTAssertEqual(error as? KeyshareSweeperError, .missingModelContext)
        }
    }

    /// With no key in hand `seal` is a passthrough, so a sweep would otherwise
    /// report success over shares it left in the clear.
    func testSealingWithNoDataKeyInHandFailsRatherThanSilentlyDoingNothing() throws {
        try givenVaults([("vault-one", [firstShare])])
        let disabled = KeyshareSweeper(
            protector: KeyshareProtector(state: { .disabled }),
            context: { [context] in context }
        )

        XCTAssertThrowsError(try disabled.sealAll()) { error in
            XCTAssertEqual(error as? KeyshareSweeperError, .verificationFailed(pubkey: "vault-one-0"))
        }
        XCTAssertEqual(try storedShares(), [firstShare])
    }

    /// `keyId` is part of the share's identity for MLDSA, and rebuilding the
    /// array is exactly where it would get dropped.
    func testSweepingPreservesTheKeyIdentifier() throws {
        let vaults = try givenVaults([("vault-one", [firstShare])])
        vaults[0].keyshares = [KeyShare(pubkey: "vault-one-0", keyshare: firstShare, keyId: "mldsa-key-id")]
        try context.save()

        try sut.sealAll()

        let share = try XCTUnwrap(try allShares().first)
        XCTAssertEqual(share.keyId, "mldsa-key-id")
    }

    // MARK: - Helpers

    /// Every `@Attribute(.unique)` field is given a distinct value per vault.
    /// `TestStore.makeVault` leaves `pubKeyEdDSA` at a shared constant, and
    /// SwiftData answers a duplicate unique key with an *upsert* rather than an
    /// error — so a multi-vault fixture built that way silently collapses to one
    /// row and every multi-vault assertion below would pass vacuously. The count
    /// check is here so that failure is loud if it ever comes back.
    @discardableResult
    private func givenVaults(_ vaults: [(String, [String])]) throws -> [Vault] {
        let inserted = vaults.map { pubKey, shares in
            let vault = Vault(
                name: "Vault \(pubKey)",
                signers: [],
                pubKeyECDSA: "ecdsa-\(pubKey)",
                pubKeyEdDSA: "eddsa-\(pubKey)",
                keyshares: shares.enumerated().map { index, value in
                    KeyShare(pubkey: "\(pubKey)-\(index)", keyshare: value)
                },
                localPartyID: "party-\(pubKey)",
                hexChainCode: "hex",
                resharePrefix: nil,
                libType: .DKLS
            )
            context.insert(vault)
            return vault
        }
        try context.save()

        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Vault>()),
            vaults.count,
            "the fixture collapsed — a unique attribute is shared between vaults"
        )
        return inserted
    }

    /// A share sealed twice under the key in hand. Built with the cipher
    /// directly, because `KeyshareProtector.seal` refuses to seal an
    /// already-sealed value — which is why the app can never produce one and an
    /// import is the only way in.
    private func nestedEnvelope() throws -> String {
        let cipher = AesGcmKeyshareCipher()
        let inner = try cipher.seal(firstShare, with: key)
        return try cipher.seal(inner, with: key)
    }

    private func allShares() throws -> [KeyShare] {
        try context.fetch(FetchDescriptor<Vault>()).flatMap(\.keyshares)
    }

    private func storedShares() throws -> [String] {
        try allShares().map(\.keyshare)
    }
}
