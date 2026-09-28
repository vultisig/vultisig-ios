//
//  SwapKitCardanoSignerTests.swift
//  VultisigAppTests
//
//  Phase 4 follow-on: pre-signing + envelope-assembly coverage for the
//  SwapKit-built Cardano CBOR flow. The Blake2b-256 digest of the embedded
//  transaction body is pinnable from the SwapKit response — if our CBOR
//  walker ever drifts on item-0 boundaries, the digest assertion fires.
//
//  Body verification: ports vultisig-android PR #5990's `verifyBody` rule
//  set. Fixtures below are built with the small `CardanoCBOR` encoder rather
//  than hand-written hex, since the matrix of shapes (legacy array vs
//  post-Alonzo map outputs, value as int vs `[coin, multiasset]`, tag 258
//  sets, disallowed fields) is too large to hand-encode reliably.
//

import BigInt
import Foundation
import WalletCore
import XCTest
@testable import VultisigApp

final class SwapKitCardanoSignerTests: XCTestCase {

    /// Real SwapKit `/v3/swap` response body (Cardano source, NEAR-routed).
    /// Single input, two outputs (deposit + change), fee 0x2888d, TTL
    /// 0x0b324cbb. Witness set is empty (`a0`) — that's the slot we fill
    /// after MPC signing.
    private static let unsignedCborHex =
        "84a40081825820f18b3c232d78ca5b1c9e5112314261d839d52a12a5c446c4f80317dc8ac60d48" +
        "000182a200581d618749053dab2309d9b9eba75e17b0406d78302503b4187ca3af260960011a02" +
        "b54eb8a200581d6148838772eed76ee662d3d444e4f8791544e62fa800eb775ec84de62e011a02" +
        "2046f7021a0002888d031a0b324cbba0f5f6"

    /// A vault key unrelated to the fixture above — these two output
    /// addresses aren't derived from it, so any body-verification test that
    /// runs against `unsignedCborHex` exercises the "neither output is ours"
    /// rejection path, not acceptance. Tests that need an *accepted* body
    /// build their own fixture around this key's derived address instead.
    private static let testVaultPubKeyEdDSA = String(repeating: "11", count: 32)

    // MARK: - Decoder routing

    func testCborTxTypeWithPrebuiltBodyDecodesAsCardanoPrebuilt() throws {
        // SwapKit's live shape: `meta.txType: "CBOR"` + `tx: "<hex>"` →
        // pre-built CBOR flow. The decoder must surface a typed
        // `.cardanoPrebuilt` case with the bytes parsed out — anything else
        // would silently route through the deposit-only path and re-build a
        // transaction with a different tx_id.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-ada-cbor-prebuilt-swap"
        )
        XCTAssertEqual(response.meta.txType, "CBOR")
        guard case .cardanoPrebuilt(let cbor) = response.tx else {
            return XCTFail("expected .cardanoPrebuilt case, got \(response.tx)")
        }
        // 67-byte body + 1-byte witness + 1-byte is_valid + 1-byte aux_data
        // header + outer array(4) header. 135 bytes total — pin the round-
        // tripped byte count so a fixture truncation surfaces here.
        XCTAssertEqual(cbor.count, 135)
        XCTAssertEqual(cbor.hexString, Self.unsignedCborHex)
    }

    // MARK: - Pre-signing digest

    /// `digest(payload:)` is a pure envelope-hashing primitive with no body
    /// verification — this pins the Blake2b-256 of the captured fixture's
    /// body (item 0 of the envelope) so drift in the CBOR walker's item-0
    /// boundary detection fires this assertion, independent of whether the
    /// body's *contents* would pass `verifyBody`. `preSigningHashes`'
    /// accept/reject behavior (which does run body verification) is covered
    /// below in the "Body verification" sections.
    func testDigestPinsBodyHashFromCapturedFixture() throws {
        let payload = makePayload()
        let digest = try SwapKitCardanoSigner.digest(payload: payload)
        XCTAssertEqual(
            digest.hexString,
            "f568726d7291983d6ba0e7fc5a00b242f0016ed38d0dd3930d86ced8963ba597"
        )
    }

    func testDigestRejectsEmptyPayload() {
        let empty = makePayload(cbor: Data())
        XCTAssertThrowsError(try SwapKitCardanoSigner.digest(payload: empty)) { err in
            guard case SwapKitCardanoSignerError.emptyPayload = err else {
                return XCTFail("expected .emptyPayload, got \(err)")
            }
        }
    }

    func testDigestRejectsMissingOuterArrayHeader() {
        // Strip the outer `84` byte — the walker must reject before hashing
        // a malformed envelope (otherwise we'd hash the wrong bytes and feed
        // a useless digest to MPC).
        var bad = Data(hexString: Self.unsignedCborHex)!
        bad.removeFirst()
        let payload = makePayload(cbor: bad)
        XCTAssertThrowsError(try SwapKitCardanoSigner.digest(payload: payload)) { err in
            guard case SwapKitCardanoSignerError.malformedEnvelope = err else {
                return XCTFail("expected .malformedEnvelope, got \(err)")
            }
        }
    }

    // MARK: - Signed-envelope assembly

    func testAssembleSignedTransactionProducesValidEnvelope() throws {
        // Dummy 32-byte vkey + 64-byte sig. We're not testing MPC here — just
        // verifying the CBOR splice keeps body / is_valid / aux_data
        // verbatim and replaces the empty witness_set with the correct
        // `{ 0: [[vkey, sig]] }` shape.
        let vkey = Data(repeating: 0, count: 32)
        let sig = Data(repeating: 0, count: 64)
        let unsigned = Data(hexString: Self.unsignedCborHex)!

        let signed = try SwapKitCardanoSigner.assembleSignedTransaction(
            unsignedCbor: unsigned,
            signature: sig,
            verificationKey: vkey
        )

        // Expected output, computed independently:
        //   array(4) header (84)
        //   + 131-byte body (verbatim)
        //   + witness: a1 00 81 82 + cbor_bytes(vkey, 34 bytes) + cbor_bytes(sig, 66 bytes)
        //   + is_valid (f5)
        //   + aux_data (f6)
        // = 1 + 131 + 104 + 1 + 1 = 238 bytes.
        XCTAssertEqual(signed.count, 238)
        XCTAssertEqual(signed[0], 0x84, "outer array(4) header preserved")

        // Body bytes preserved verbatim — drift here would invalidate the
        // signature even if the envelope re-encoded to the same hex string.
        let bodyRange = 1..<132
        let unsignedBody = unsigned[bodyRange]
        let signedBody = signed[bodyRange]
        XCTAssertEqual(Data(unsignedBody), Data(signedBody))

        // Witness immediately follows the body. Expected encoding:
        //   a1 00 81 82 5820 <32 vkey bytes> 5840 <64 sig bytes>
        let expectedWitnessHex =
            "a10081825820" +
            String(repeating: "00", count: 32) +
            "5840" +
            String(repeating: "00", count: 64)
        let witnessStart = 132
        let witnessEnd = witnessStart + 104
        XCTAssertEqual(
            Data(signed[witnessStart..<witnessEnd]).hexString,
            expectedWitnessHex,
            "witness_set must be `{ 0: [[vkey_32, sig_64]] }`"
        )

        // is_valid and aux_data tail bytes verbatim.
        XCTAssertEqual(signed[signed.count - 2], 0xF5)
        XCTAssertEqual(signed[signed.count - 1], 0xF6)
    }

    func testAssembleRejectsBadKeyLength() {
        let unsigned = Data(hexString: Self.unsignedCborHex)!
        XCTAssertThrowsError(try SwapKitCardanoSigner.assembleSignedTransaction(
            unsignedCbor: unsigned,
            signature: Data(repeating: 0, count: 64),
            verificationKey: Data(repeating: 0, count: 31)
        )) { err in
            guard case CardanoSignedTxBuilderError.invalidPublicKeyLength(let n) = err else {
                return XCTFail("expected .invalidPublicKeyLength, got \(err)")
            }
            XCTAssertEqual(n, 31)
        }
    }

    func testAssembleRejectsBadSignatureLength() {
        let unsigned = Data(hexString: Self.unsignedCborHex)!
        XCTAssertThrowsError(try SwapKitCardanoSigner.assembleSignedTransaction(
            unsignedCbor: unsigned,
            signature: Data(repeating: 0, count: 63),
            verificationKey: Data(repeating: 0, count: 32)
        )) { err in
            guard case CardanoSignedTxBuilderError.invalidSignatureLength(let n) = err else {
                return XCTFail("expected .invalidSignatureLength, got \(err)")
            }
            XCTAssertEqual(n, 63)
        }
    }

    // MARK: - Enterprise-address derivation parity

    /// The 0x61 ‖ blake2b-224(vkey) formula `verifyBody` uses to compute
    /// "the vault's own output" must be byte-identical to the app's existing
    /// Cardano address derivation, or a legitimate change output would be
    /// misclassified as external and rejected. `CoinFactory` only exposes
    /// the bech32-encoded string, so compare by encoding our raw bytes with
    /// the same HRP and asserting the strings match.
    func testEnterpriseAddressDerivationMatchesCoinFactoryByteForByte() throws {
        let keys = [
            String(repeating: "11", count: 32),
            String(repeating: "22", count: 32),
            (String(repeating: "ab", count: 16) + String(repeating: "cd", count: 15) + "ef")
        ]
        for key in keys {
            let rawAddress = Self.vaultAddress(forHexKey: key)
            let expectedBech32 = try CoinFactory.createCardanoEnterpriseAddress(spendingKeyHex: key)
            XCTAssertEqual(
                Bech32.encode(hrp: "addr", data: rawAddress),
                expectedBech32,
                "blake2b-224 enterprise-address bytes must match CoinFactory's derivation for key \(key)"
            )
        }
    }

    // MARK: - Body verification: accepted

    func testAcceptsChangeOnlyBody() throws {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let body = Self.makeBody(outputs: [Self.makeOutput(address: vault, lovelace: 1_000_000)])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        let hashes = try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key)
        XCTAssertEqual(hashes.count, 1)
        XCTAssertEqual(hashes[0], try SwapKitCardanoSigner.digest(payload: payload).hexString)
    }

    func testAcceptsSingleDepositWithinQuotePlusVaultChange() throws {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let deposit = Data(repeating: 0x99, count: 29)
        let body = Self.makeBody(outputs: [
            Self.makeOutput(address: deposit, lovelace: 40_000_000),
            Self.makeOutput(address: vault, lovelace: 5_000_000)
        ])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body), fromAmount: BigInt(45_500_000))
        XCTAssertNoThrow(try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key))
    }

    func testAcceptsDepositEqualToQuote() throws {
        // Boundary: deposit == fromAmount exactly — Android/iOS both use <=.
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let deposit = Data(repeating: 0x99, count: 29)
        let body = Self.makeBody(outputs: [
            Self.makeOutput(address: deposit, lovelace: 45_500_000),
            Self.makeOutput(address: vault, lovelace: 100_000)
        ])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body), fromAmount: BigInt(45_500_000))
        XCTAssertNoThrow(try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key))
    }

    func testAcceptsMultipleVaultOutputsCarryingNativeTokens() throws {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let body = Self.makeBody(outputs: [
            Self.makeOutput(address: vault, lovelace: 2_000_000, hasAssets: true),
            Self.makeOutput(address: vault, lovelace: 1_500_000)
        ])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertNoThrow(try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key))
    }

    func testAcceptsLegacyArrayShapedOutputs() throws {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let legacyVaultOutput = CardanoCBOR.array([CardanoCBOR.bytes(vault), CardanoCBOR.uint(3_000_000)])
        let body = Self.makeBody(outputs: [legacyVaultOutput])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertNoThrow(try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key))
    }

    func testAcceptsBodyWithAllPassiveFieldsPresent() throws {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let body = Self.makeBody(
            outputs: [Self.makeOutput(address: vault, lovelace: 1_000_000)],
            extraFields: [
                (3, CardanoCBOR.uint(190_000_000)),
                (7, CardanoCBOR.bytes(Data(repeating: 0xaa, count: 32))),
                (8, CardanoCBOR.uint(189_000_000)),
                (15, CardanoCBOR.uint(1))
            ]
        )
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertNoThrow(try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key))
    }

    func testAcceptsOutputsWrappedInSet258Tag() throws {
        // Defensive parity with Android's tag-258 unwrap — not a realistic
        // shape for `outputs` on real Cardano CDDL, but proves the reader
        // tolerates it exactly like the Kotlin `CborReader` does.
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let outputsArray = CardanoCBOR.array([Self.makeOutput(address: vault, lovelace: 1_000_000)])
        let taggedOutputs = CardanoCBOR.setTag(outputsArray)
        let body = CardanoCBOR.map([
            (0, Self.inputsField),
            (1, taggedOutputs),
            (2, CardanoCBOR.uint(170_000))
        ])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertNoThrow(try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key))
    }

    func testAcceptsFeeAtCeiling() throws {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let body = Self.makeBody(outputs: [Self.makeOutput(address: vault, lovelace: 1_000_000)], fee: 2_000_000)
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertNoThrow(try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key))
    }

    func testAcceptsCapturedFixtureShapeRekeyedToTestVault() throws {
        // Mirrors Android's disclosed-but-uncommitted "captured tx re-keyed
        // to a test vault: accepted" ad hoc check — same shape (1 input,
        // deposit + change, real fixture's fee/ttl/output values) as the
        // captured fixture above, with output addresses replaced so the
        // change output is provably ours.
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let deposit = Data(repeating: 0x99, count: 29)
        let body = Self.makeBody(
            outputs: [
                Self.makeOutput(address: deposit, lovelace: 45_436_600),
                Self.makeOutput(address: vault, lovelace: 35_669_751)
            ],
            fee: 166_029,
            extraFields: [(3, CardanoCBOR.uint(187_845_819))]
        )
        let payload = makePayload(cbor: Self.makeEnvelope(body: body), fromAmount: BigInt(45_500_000))
        XCTAssertNoThrow(try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key))
    }

    // MARK: - Body verification: rejected

    func testPreSigningHashesRejectsRealFixtureAgainstUnrelatedVault() {
        // The real captured fixture's two outputs don't belong to any vault
        // we hold the key for. Checked against an unrelated key, neither
        // matches, so the second one trips "at most one output outside the
        // vault". Mirrors Android's disclosed "non-vault source / change
        // sent elsewhere: rejected" ad hoc check, using the real payload.
        let payload = makePayload()
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: Self.testVaultPubKeyEdDSA)
        ) { err in
            guard case SwapKitCardanoSignerError.tooManyExternalOutputs = err else {
                return XCTFail("expected .tooManyExternalOutputs, got \(err)")
            }
        }
    }

    func testRejectsDepositAboveQuote() {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let deposit = Data(repeating: 0x99, count: 29)
        let body = Self.makeBody(outputs: [
            Self.makeOutput(address: deposit, lovelace: 45_500_001),
            Self.makeOutput(address: vault, lovelace: 100_000)
        ])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body), fromAmount: BigInt(45_500_000))
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key)
        ) { err in
            guard case SwapKitCardanoSignerError.depositExceedsQuote(let lovelace) = err else {
                return XCTFail("expected .depositExceedsQuote, got \(err)")
            }
            XCTAssertEqual(lovelace, 45_500_001)
        }
    }

    func testRejectsNativeTokensOnDeposit() {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let deposit = Data(repeating: 0x99, count: 29)
        let body = Self.makeBody(outputs: [
            Self.makeOutput(address: deposit, lovelace: 1_000_000, hasAssets: true),
            Self.makeOutput(address: vault, lovelace: 100_000)
        ])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key)
        ) { err in
            guard case SwapKitCardanoSignerError.depositNotPlainADA = err else {
                return XCTFail("expected .depositNotPlainADA, got \(err)")
            }
        }
    }

    func testRejectsDepositWithDatumExtras() {
        let key = Self.testVaultPubKeyEdDSA
        let deposit = Data(repeating: 0x99, count: 29)
        let legacyDeposit = CardanoCBOR.array([
            CardanoCBOR.bytes(deposit),
            CardanoCBOR.uint(1_000_000),
            CardanoCBOR.bytes(Data(repeating: 0xde, count: 32)) // datum_hash
        ])
        let body = Self.makeBody(outputs: [legacyDeposit])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key)
        ) { err in
            guard case SwapKitCardanoSignerError.depositNotPlainADA = err else {
                return XCTFail("expected .depositNotPlainADA, got \(err)")
            }
        }
    }

    func testRejectsMoreThanOneExternalOutput() {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let body = Self.makeBody(outputs: [
            Self.makeOutput(address: Data(repeating: 0x99, count: 29), lovelace: 1_000_000),
            Self.makeOutput(address: Data(repeating: 0x88, count: 29), lovelace: 1_000_000),
            Self.makeOutput(address: vault, lovelace: 100_000)
        ])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key)
        ) { err in
            guard case SwapKitCardanoSignerError.tooManyExternalOutputs = err else {
                return XCTFail("expected .tooManyExternalOutputs, got \(err)")
            }
        }
    }

    func testRejectsMissingOutputs() {
        let key = Self.testVaultPubKeyEdDSA
        let body = CardanoCBOR.map([(0, Self.inputsField), (2, CardanoCBOR.uint(170_000))])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key)
        ) { err in
            guard case SwapKitCardanoSignerError.missingOutputs = err else {
                return XCTFail("expected .missingOutputs, got \(err)")
            }
        }
    }

    func testRejectsMissingFee() {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let outputs = CardanoCBOR.array([Self.makeOutput(address: vault, lovelace: 1_000_000)])
        let body = CardanoCBOR.map([(0, Self.inputsField), (1, outputs)])
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key)
        ) { err in
            guard case SwapKitCardanoSignerError.missingFee = err else {
                return XCTFail("expected .missingFee, got \(err)")
            }
        }
    }

    func testRejectsFeeAboveCeiling() {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let body = Self.makeBody(outputs: [Self.makeOutput(address: vault, lovelace: 1_000_000)], fee: 2_000_001)
        let payload = makePayload(cbor: Self.makeEnvelope(body: body))
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key)
        ) { err in
            guard case SwapKitCardanoSignerError.feeExceedsCeiling(let fee) = err else {
                return XCTFail("expected .feeExceedsCeiling, got \(err)")
            }
            XCTAssertEqual(fee, 2_000_001)
        }
    }

    func testRejectsEachDisallowedBodyField() {
        let key = Self.testVaultPubKeyEdDSA
        let vault = Self.vaultAddress(forHexKey: key)
        let outputs = CardanoCBOR.array([Self.makeOutput(address: vault, lovelace: 1_000_000)])
        // Certs(4), withdrawals(5), update(6), mint(9), collateral(13/16/17),
        // required signers(14), reference inputs(18), governance(19-22) — a
        // plain payment never carries any of these.
        let disallowedKeys: [UInt64] = [4, 5, 6, 9, 13, 14, 16, 17, 18, 19, 20, 21, 22]
        for disallowedKey in disallowedKeys {
            let body = CardanoCBOR.map([
                (0, Self.inputsField),
                (1, outputs),
                (2, CardanoCBOR.uint(170_000)),
                (disallowedKey, CardanoCBOR.uint(0))
            ])
            let payload = makePayload(cbor: Self.makeEnvelope(body: body))
            XCTAssertThrowsError(
                try SwapKitCardanoSigner.preSigningHashes(payload: payload, vaultPubKeyEdDSA: key),
                "expected field \(disallowedKey) to be rejected"
            ) { err in
                guard case SwapKitCardanoSignerError.disallowedBodyField(let rejectedKey) = err else {
                    return XCTFail("expected .disallowedBodyField for key \(disallowedKey), got \(err)")
                }
                XCTAssertEqual(rejectedKey, disallowedKey)
            }
        }
    }

    func testCompileSignedTransactionAlsoVerifiesBody() throws {
        // The signing entry point runs the same check as the pre-signing
        // hash — a co-signer that somehow reaches this stage with a
        // malicious body still refuses to sign it. `compileSignedTransaction`
        // constructs a real WalletCore ed25519 `PublicKey` from `pubKeyHex`
        // before body verification even runs, so the key needs to be a
        // genuine curve point — derive one instead of reusing the arbitrary
        // `testVaultPubKeyEdDSA` bytes `preSigningHashes` is happy to hash
        // without validating.
        let privateKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x11, count: 32)))
        let validEd25519PubKeyHex = privateKey.getPublicKeyEd25519().data.hexString
        let payload = makePayload()
        XCTAssertThrowsError(
            try SwapKitCardanoSigner.compileSignedTransaction(
                payload: payload,
                signatures: [:],
                pubKeyHex: validEd25519PubKeyHex
            )
        ) { err in
            guard case SwapKitCardanoSignerError.tooManyExternalOutputs = err else {
                return XCTFail("expected .tooManyExternalOutputs, got \(err)")
            }
        }
    }

    // MARK: - Helpers

    private func makePayload(cbor: Data? = nil, fromAmount: BigInt = BigInt(45_500_000)) -> SwapKitSwapPayload {
        let bytes = cbor ?? Data(hexString: Self.unsignedCborHex)!
        return SwapKitSwapPayload(
            fromCoin: makeAdaCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: fromAmount,
            toAmountDecimal: 0,
            txType: "CARDANO_PREBUILT",
            txPayload: bytes,
            targetAddress: "addr1vy9sgnlkxkwg58axypgwllhgt522k045f0q7zst5faxqc2sgggj3a",
            inboundAddress: "addr1vy9sgnlkxkwg58axypgwllhgt522k045f0q7zst5faxqc2sgggj3a",
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
    }

    private func makeAdaCoin() -> Coin {
        let meta = CoinMeta.make(chain: .cardano, ticker: "ADA", decimals: 6, isNativeToken: true)
        return Coin(
            asset: meta,
            address: "addr1v9yg8pmjamtkaenz602yfe8c0y25fe304qqwka67epx7vtszj8749",
            hexPublicKey: ""
        )
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }

    /// `0x61 ‖ blake2b-224(pubkey)` — the raw bytes `verifyBody` computes
    /// internally for "the vault's own address". Kept in the test target
    /// (mirroring, not calling, the production `private` implementation) so
    /// fixtures can target a specific key's derived address.
    private static func vaultAddress(forHexKey hexKey: String) -> Data {
        let pubKeyData = Data(hexString: hexKey)!
        let hash = Hash.blake2b(data: pubKeyData, size: 28)
        return Data([0x61]) + hash
    }

    private static let inputsField = CardanoCBOR.array([
        CardanoCBOR.array([CardanoCBOR.bytes(Data(repeating: 0x22, count: 32)), CardanoCBOR.uint(0)])
    ])

    private static func makeOutput(address: Data, lovelace: UInt64, hasAssets: Bool = false) -> Data {
        let value: Data = hasAssets
            ? CardanoCBOR.array([CardanoCBOR.uint(lovelace), CardanoCBOR.map([])])
            : CardanoCBOR.uint(lovelace)
        return CardanoCBOR.map([(0, CardanoCBOR.bytes(address)), (1, value)])
    }

    private static func makeBody(
        outputs: [Data],
        fee: UInt64 = 170_000,
        extraFields: [(UInt64, Data)] = []
    ) -> Data {
        var fields: [(UInt64, Data)] = [
            (0, inputsField),
            (1, CardanoCBOR.array(outputs)),
            (2, CardanoCBOR.uint(fee))
        ]
        fields.append(contentsOf: extraFields)
        return CardanoCBOR.map(fields)
    }

    private static func makeEnvelope(body: Data) -> Data {
        var envelope = Data()
        envelope.append(0x84)
        envelope.append(body)
        envelope.append(Data([0xA0])) // empty witness set
        envelope.append(Data([0xF5])) // is_valid = true
        envelope.append(Data([0xF6])) // aux_data = null
        return envelope
    }
}

/// Minimal definite-length CBOR encoder for building test fixtures. Not
/// general-purpose (no negative ints, no text strings, no indefinite
/// lengths) — just enough to construct Cardano transaction bodies.
private enum CardanoCBOR {
    static func uint(_ value: UInt64) -> Data { head(major: 0, argument: value) }

    static func bytes(_ data: Data) -> Data { head(major: 2, argument: UInt64(data.count)) + data }

    static func array(_ items: [Data]) -> Data {
        head(major: 4, argument: UInt64(items.count)) + items.reduce(Data(), +)
    }

    static func map(_ pairs: [(UInt64, Data)]) -> Data {
        let encodedPairs = pairs.flatMap { [uint($0.0), $0.1] }
        return head(major: 5, argument: UInt64(pairs.count)) + encodedPairs.reduce(Data(), +)
    }

    /// Wraps `inner` in a CBOR tag(258) header (`d9 01 02`) — the Conway-era
    /// "set" encoding a couple of collection types may use.
    static func setTag(_ inner: Data) -> Data {
        Data([0xD9, 0x01, 0x02]) + inner
    }

    private static func head(major: UInt8, argument: UInt64) -> Data {
        var data = Data()
        switch argument {
        case 0...23:
            data.append(major << 5 | UInt8(argument))
        case 24...0xFF:
            data.append(major << 5 | 24)
            data.append(UInt8(argument))
        case 0x100...0xFFFF:
            data.append(major << 5 | 25)
            data.append(UInt8((argument >> 8) & 0xFF))
            data.append(UInt8(argument & 0xFF))
        case 0x1_0000...0xFFFF_FFFF:
            data.append(major << 5 | 26)
            data.append(UInt8((argument >> 24) & 0xFF))
            data.append(UInt8((argument >> 16) & 0xFF))
            data.append(UInt8((argument >> 8) & 0xFF))
            data.append(UInt8(argument & 0xFF))
        default:
            data.append(major << 5 | 27)
            for shift in stride(from: 56, through: 0, by: -8) {
                data.append(UInt8((argument >> UInt64(shift)) & 0xFF))
            }
        }
        return data
    }
}
