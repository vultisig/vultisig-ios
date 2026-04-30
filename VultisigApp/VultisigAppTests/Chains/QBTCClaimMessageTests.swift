//
//  QBTCClaimMessageTests.swift
//  VultisigAppTests
//
//  Byte-parity tests vs vultisig-sdk/.../buildClaimTx.test.ts plus
//  structural tests asserting the wire format matches the SDK encoder.
//

@testable import VultisigApp
import XCTest

final class QBTCClaimMessageTests: XCTestCase {
    // Same fixture as `vultisig-sdk/.../buildClaimTx.test.ts`.
    static let validClaimer = "qbtc1abc"
    static let validProof = String(repeating: "ff", count: 200)
    static let validMessageHash = String(repeating: "bb", count: 32)
    static let validAddressHash = String(repeating: "cc", count: 20)
    static let validQbtcAddressHash = String(repeating: "dd", count: 32)
    static let validPubKeyHashSha256 = String(repeating: "ee", count: 32)
    static let validUtxo = ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 1000)

    static func makeInput(
        claimer: String = validClaimer,
        utxos: [ClaimableUtxo] = [validUtxo],
        proofHex: String = validProof,
        messageHashHex: String = validMessageHash,
        addressHashHex: String = validAddressHash,
        qbtcAddressHashHex: String = validQbtcAddressHash,
        pubKeyHashSha256Hex: String = validPubKeyHashSha256
    ) -> QBTCClaimMessage {
        QBTCClaimMessage(
            claimer: claimer,
            utxos: utxos,
            proofHex: proofHex,
            messageHashHex: messageHashHex,
            addressHashHex: addressHashHex,
            qbtcAddressHashHex: qbtcAddressHashHex,
            pubKeyHashSha256Hex: pubKeyHashSha256Hex
        )
    }

    static let validInput = makeInput()

    // MARK: - validateClaimInput

    func testValidateAcceptsValidInput() {
        XCTAssertNoThrow(try QBTCHelper.validateClaimInput(Self.validInput))
    }

    func testValidateRejectsEmptyUtxos() {
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(Self.makeInput(utxos: []))) { error in
            guard let err = error as? QBTCClaimMessageError, case .utxoCountOutOfRange(0) = err else {
                return XCTFail("expected utxoCountOutOfRange(0), got \(error)")
            }
        }
    }

    func testValidateRejectsMoreThan50Utxos() {
        let utxos = (0..<51).map { i in
            ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: UInt32(i), amount: 1)
        }
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(Self.makeInput(utxos: utxos))) { error in
            guard let err = error as? QBTCClaimMessageError, case .utxoCountOutOfRange(51) = err else {
                return XCTFail("expected utxoCountOutOfRange(51), got \(error)")
            }
        }
    }

    func testValidateRejectsDuplicateUtxos() {
        let dupe = ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 1)
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(Self.makeInput(utxos: [dupe, dupe]))) { error in
            guard let err = error as? QBTCClaimMessageError, case .duplicateUtxo = err else {
                return XCTFail("expected duplicateUtxo, got \(error)")
            }
        }
    }

    func testValidateRejectsInvalidTxidLength() {
        let utxo = ClaimableUtxo(txid: String(repeating: "aa", count: 16), vout: 0, amount: 1)
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(Self.makeInput(utxos: [utxo]))) { error in
            guard let err = error as? QBTCClaimMessageError, case .invalidTxid = err else {
                return XCTFail("expected invalidTxid, got \(error)")
            }
        }
    }

    func testValidateRejectsNonHexTxid() {
        let utxo = ClaimableUtxo(txid: String(repeating: "zz", count: 32), vout: 0, amount: 1)
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(Self.makeInput(utxos: [utxo]))) { error in
            guard let err = error as? QBTCClaimMessageError, case .invalidTxid = err else {
                return XCTFail("expected invalidTxid, got \(error)")
            }
        }
    }

    func testValidateRejectsProofTooSmall() {
        let bad = Self.makeInput(proofHex: String(repeating: "ff", count: 50))
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(bad)) { error in
            guard let err = error as? QBTCClaimMessageError, case .proofTooSmall = err else {
                return XCTFail("expected proofTooSmall, got \(error)")
            }
        }
    }

    func testValidateRejectsProofTooLarge() {
        let bad = Self.makeInput(proofHex: String(repeating: "ff", count: 60_000))
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(bad)) { error in
            guard let err = error as? QBTCClaimMessageError, case .proofTooLarge = err else {
                return XCTFail("expected proofTooLarge, got \(error)")
            }
        }
    }

    func testValidateRejectsInvalidMessageHashLength() {
        let bad = Self.makeInput(messageHashHex: String(repeating: "aa", count: 16))
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(bad)) { error in
            guard let err = error as? QBTCClaimMessageError,
                  case .invalidHexField(let name, _, _) = err else {
                return XCTFail("expected invalidHexField, got \(error)")
            }
            XCTAssertEqual(name, "message_hash")
        }
    }

    func testValidateRejectsInvalidAddressHashLength() {
        let bad = Self.makeInput(addressHashHex: String(repeating: "aa", count: 16))
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(bad)) { error in
            guard let err = error as? QBTCClaimMessageError,
                  case .invalidHexField(let name, _, _) = err else {
                return XCTFail("expected invalidHexField, got \(error)")
            }
            XCTAssertEqual(name, "address_hash")
        }
    }

    func testValidateRejectsInvalidQbtcAddressHashLength() {
        let bad = Self.makeInput(qbtcAddressHashHex: String(repeating: "aa", count: 16))
        XCTAssertThrowsError(try QBTCHelper.validateClaimInput(bad)) { error in
            guard let err = error as? QBTCClaimMessageError,
                  case .invalidHexField(let name, _, _) = err else {
                return XCTFail("expected invalidHexField, got \(error)")
            }
            XCTAssertEqual(name, "qbtc_address_hash")
        }
    }

    // MARK: - buildClaimTxBody

    func testBuildClaimTxBodyProducesNonEmptyBytes() throws {
        let result = try QBTCHelper.buildClaimTxBody(Self.validInput)
        XCTAssertGreaterThan(result.count, 0)
    }

    func testBuildClaimTxBodyHandlesMultipleUtxos() throws {
        let multi = Self.makeInput(utxos: [
            ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 1),
            ClaimableUtxo(txid: String(repeating: "bb", count: 32), vout: 1, amount: 2)
        ])
        let result = try QBTCHelper.buildClaimTxBody(multi)
        XCTAssertGreaterThan(result.count, 0)
    }

    // MARK: - Wire-format byte parity (the load-bearing parity check)

    /// `vout = 0` MUST be encoded as a UTXORef containing only field 1 (txid).
    /// This is the proto3 default-skip behaviour the chain depends on.
    func testEncodeUtxoRefSkipsZeroVout() {
        let utxo = ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 1)
        let encoded = QBTCHelper.encodeUtxoRef(utxo)

        var expected = Data()
        expected.appendProtoString(fieldNumber: 1, value: utxo.txid)

        XCTAssertEqual(encoded, expected)
    }

    /// `vout = 1` (or any non-zero) MUST encode both fields.
    func testEncodeUtxoRefIncludesNonZeroVout() {
        let utxo = ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 1, amount: 1)
        let encoded = QBTCHelper.encodeUtxoRef(utxo)

        var expected = Data()
        expected.appendProtoString(fieldNumber: 1, value: utxo.txid)
        expected.appendProtoVarint(fieldNumber: 2, value: 1)

        XCTAssertEqual(encoded, expected)
    }

    /// `MsgClaimWithProof` MUST emit fields in field-number order
    /// (claimer=1, utxos=2..., proof=3, messageHash=4, addressHash=5,
    /// qbtcAddressHash=6, pubKeyHashSha256=7) with repeated UTXOs as separate
    /// length-delimited records (NOT packed).
    func testEncodeMsgClaimWithProofMatchesManualReconstruction() {
        let encoded = QBTCHelper.encodeMsgClaimWithProof(Self.validInput)

        var expected = Data()
        expected.appendProtoString(fieldNumber: 1, value: Self.validInput.claimer)
        for utxo in Self.validInput.utxos {
            expected.appendProtoBytes(fieldNumber: 2, data: QBTCHelper.encodeUtxoRef(utxo))
        }
        expected.appendProtoString(fieldNumber: 3, value: Self.validInput.proofHex)
        expected.appendProtoString(fieldNumber: 4, value: Self.validInput.messageHashHex)
        expected.appendProtoString(fieldNumber: 5, value: Self.validInput.addressHashHex)
        expected.appendProtoString(fieldNumber: 6, value: Self.validInput.qbtcAddressHashHex)
        expected.appendProtoString(fieldNumber: 7, value: Self.validInput.pubKeyHashSha256Hex)

        XCTAssertEqual(encoded, expected)
    }

    /// `buildClaimWithProofAny` MUST produce: typeURL string (field 1) + the
    /// MsgClaimWithProof bytes wrapped as field 2 (length-delimited).
    func testBuildClaimWithProofAnyHasCorrectShape() throws {
        let any = try QBTCHelper.buildClaimWithProofAny(Self.validInput)

        var expected = Data()
        expected.appendProtoString(fieldNumber: 1, value: QBTCClaimConfig.msgClaimWithProofTypeURL)
        expected.appendProtoBytes(fieldNumber: 2, data: QBTCHelper.encodeMsgClaimWithProof(Self.validInput))

        XCTAssertEqual(any, expected)
    }

    /// `buildClaimTxBody` MUST wrap the Any in TxBody field 1.
    func testBuildClaimTxBodyWrapsAnyAsField1() throws {
        let body = try QBTCHelper.buildClaimTxBody(Self.validInput)
        let anyMsg = try QBTCHelper.buildClaimWithProofAny(Self.validInput)

        var expected = Data()
        expected.appendProtoBytes(fieldNumber: 1, data: anyMsg)

        XCTAssertEqual(body, expected)
    }
}
