//
//  CardanoSignedTxBuilderTests.swift
//  VultisigApp
//

@testable import VultisigApp
import WalletCore
import XCTest

/// Byte-parity fixtures shared with the SDK's
/// `packages/sdk/tests/unit/chains/cardano.test.ts`. The pubkey/signature/body
/// inputs and the expected envelope + Blake2b-256 body hash hex are pinned to
/// the same values on both platforms — any drift in either implementation
/// breaks one of these tests.
final class CardanoSignedTxBuilderTests: XCTestCase {

    // Same constants as `PUB_KEY` / `SIGNATURE` in the SDK test file.
    private let pubkey = Data(repeating: 0x11, count: 32)
    private let sig = Data(repeating: 0x22, count: 64)

    // SDK test: `MINIMAL_BODY_HEX = 'a10200'` — minimal Shelley body { fee: 0 }.
    private let minimalBodyHex = "a10200"

    // SDK test: text-keyed `{ "hi": 42 }`. Re-encoding through a CBOR encoder
    // would canonicalise this differently, breaking the signature.
    private let verbatimBodyHex = "a1626869182a"

    // Blake2b-256 of `a10200` — the sighash that goes to MPC, and is also
    // the Cardano txid. Computed with `blake2b(body, { dkLen: 32 })`.
    private let minimalBodyHashHex = "e643da0cf5d24591cb32b2a5e658b2c4659f39ce35c981f62e0abc28e065ada7"

    // MARK: - Full envelope byte-parity (matches SDK `buildSignedCardanoTx`)

    func testBuildProducesExpectedEnvelope() throws {
        let body = Data(hexString: minimalBodyHex)!
        let signed = try CardanoSignedTxBuilder.build(txBody: body, publicKey: pubkey, signature: sig)

        // 84                         array(4)
        //   <body bytes verbatim>    a1 02 00
        //   <witness set>             a1 00 81 82 5820 <pk> 5840 <sig>
        //   f5                        true
        //   f6                        null
        let expectedHex = "84"
            + minimalBodyHex
            + "a10081825820"
            + String(repeating: "11", count: 32)
            + "5840"
            + String(repeating: "22", count: 64)
            + "f5f6"
        XCTAssertEqual(signed.hexString.lowercased(), expectedHex)
    }

    func testBuildPreservesTxBodyVerbatim() throws {
        // Body that would round-trip differently through a "smart" CBOR
        // encoder (text-keyed map, single-byte uint becoming two bytes).
        let body = Data(hexString: verbatimBodyHex)!
        let signed = try CardanoSignedTxBuilder.build(txBody: body, publicKey: pubkey, signature: sig)
        XCTAssertEqual(signed[1..<(1 + body.count)], body)
        XCTAssertTrue(signed.hexString.lowercased().hasPrefix("84" + verbatimBodyHex))
    }

    // MARK: - Body hash byte-parity (matches SDK `cardanoTxBodyHash`)

    func testBodyHashMatchesSdkCardanoTxBodyHash() throws {
        // Cardano defines txid as Blake2b-256 of the body. iOS hashes via
        // WalletCore (`Hash.blake2b`) and the SDK uses `@noble/hashes/blake2b`
        // — both must produce the same hex for the same body.
        let body = Data(hexString: minimalBodyHex)!
        let hash = Hash.blake2b(data: body, size: 32)
        XCTAssertEqual(hash.hexString.lowercased(), minimalBodyHashHex)
    }

    // MARK: - cborBytes length encoding

    func testCborBytesShortLength() {
        let data = Data([0x01, 0x02, 0x03])
        XCTAssertEqual(CardanoSignedTxBuilder.cborBytes(data), Data([0x43, 0x01, 0x02, 0x03]))
    }

    func testCborBytesEmpty() {
        XCTAssertEqual(CardanoSignedTxBuilder.cborBytes(Data()), Data([0x40]))
    }

    func testCborBytesBelow24Boundary() {
        let data = Data(repeating: 0xCC, count: 23)
        let out = CardanoSignedTxBuilder.cborBytes(data)
        XCTAssertEqual(out[0], 0x40 | 23)
        XCTAssertEqual(out.count, 1 + 23)
    }

    func testCborBytesAt24() {
        let data = Data(repeating: 0xCC, count: 24)
        let out = CardanoSignedTxBuilder.cborBytes(data)
        XCTAssertEqual(out[0], 0x58)
        XCTAssertEqual(out[1], 24)
        XCTAssertEqual(out.count, 2 + 24)
    }

    func testCborBytesAt255() {
        let data = Data(repeating: 0xCC, count: 255)
        let out = CardanoSignedTxBuilder.cborBytes(data)
        XCTAssertEqual(out[0], 0x58)
        XCTAssertEqual(out[1], 255)
        XCTAssertEqual(out.count, 2 + 255)
    }

    func testCborBytesAt256() {
        let data = Data(repeating: 0xCC, count: 256)
        let out = CardanoSignedTxBuilder.cborBytes(data)
        XCTAssertEqual(out[0], 0x59)
        XCTAssertEqual(out[1], 0x01)
        XCTAssertEqual(out[2], 0x00)
        XCTAssertEqual(out.count, 3 + 256)
    }

    func testCborBytesAt65535() {
        let data = Data(repeating: 0xCC, count: 65535)
        let out = CardanoSignedTxBuilder.cborBytes(data)
        XCTAssertEqual(out[0], 0x59)
        XCTAssertEqual(out[1], 0xFF)
        XCTAssertEqual(out[2], 0xFF)
        XCTAssertEqual(out.count, 3 + 65535)
    }

    // MARK: - Validation

    func testRejectsInvalidPublicKeyLength() {
        let badKey = Data(repeating: 0xAA, count: 31)
        XCTAssertThrowsError(try CardanoSignedTxBuilder.build(txBody: Data([0xA0]), publicKey: badKey, signature: sig)) { error in
            XCTAssertEqual(error as? CardanoSignedTxBuilderError, .invalidPublicKeyLength(31))
        }
    }

    func testRejectsInvalidSignatureLength() {
        let badSig = Data(repeating: 0xBB, count: 65)
        XCTAssertThrowsError(try CardanoSignedTxBuilder.build(txBody: Data([0xA0]), publicKey: pubkey, signature: badSig)) { error in
            XCTAssertEqual(error as? CardanoSignedTxBuilderError, .invalidSignatureLength(65))
        }
    }

    func testAcceptsLargeTxBody() throws {
        // No artificial 64 KiB limit on the body — the envelope appends it
        // verbatim, not via a length-prefixed CBOR field.
        let body = Data(repeating: 0xCC, count: 70_000)
        let signed = try CardanoSignedTxBuilder.build(txBody: body, publicKey: pubkey, signature: sig)
        XCTAssertEqual(signed[1..<(1 + body.count)], body)
    }
}
