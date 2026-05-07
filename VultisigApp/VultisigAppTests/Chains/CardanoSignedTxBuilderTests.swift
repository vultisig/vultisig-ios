//
//  CardanoSignedTxBuilderTests.swift
//  VultisigApp
//

@testable import VultisigApp
import XCTest

final class CardanoSignedTxBuilderTests: XCTestCase {

    private let pubkey = Data(repeating: 0xAA, count: 32)
    private let sig = Data(repeating: 0xBB, count: 64)

    // MARK: - Full envelope byte-parity

    func testBuildProducesExpectedEnvelope() throws {
        let body = Data([0xA0]) // 1-byte body (CBOR empty map for arbitrary fixture)
        let signed = try CardanoSignedTxBuilder.build(txBody: body, publicKey: pubkey, signature: sig)

        var expected = Data()
        expected.append(0x84) // outer array(4)
        expected.append(body)
        expected.append(contentsOf: [0xA1, 0x00, 0x81, 0x82]) // witness header
        expected.append(contentsOf: [0x58, 0x20]) // bytes(32) for pubkey
        expected.append(pubkey)
        expected.append(contentsOf: [0x58, 0x40]) // bytes(64) for signature
        expected.append(sig)
        expected.append(0xF5) // isValid = true
        expected.append(0xF6) // auxiliary_data = null
        XCTAssertEqual(signed, expected)
    }

    func testBuildPreservesTxBodyVerbatim() throws {
        // Tx body must NOT be re-encoded. Use a body with bytes that a naive
        // CBOR encoder might canonicalise (e.g. uint widths, map key order).
        let body = Data([0xA3, 0x00, 0x81, 0x82, 0xD8, 0x18, 0x42, 0x10, 0xFF])
        let signed = try CardanoSignedTxBuilder.build(txBody: body, publicKey: pubkey, signature: sig)
        XCTAssertEqual(signed[1..<(1 + body.count)], body)
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

    func testRejectsBodyTooLarge() {
        let huge = Data(repeating: 0x01, count: 65536)
        XCTAssertThrowsError(try CardanoSignedTxBuilder.build(txBody: huge, publicKey: pubkey, signature: sig)) { error in
            XCTAssertEqual(error as? CardanoSignedTxBuilderError, .bodyTooLarge(65536))
        }
    }
}
