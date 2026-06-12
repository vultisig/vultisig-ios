//
//  QBTCClaimHashesTests.swift
//  VultisigAppTests
//
//  Byte-parity tests vs vultisig-sdk/.../computeClaimHashes.test.ts.
//  If any of these fail, the QBTC claim flow will not be accepted by the chain.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class QBTCClaimHashesTests: XCTestCase {
    // The secp256k1 generator point's compressed encoding.
    // Same fixture as the SDK test (`computeClaimHashes.test.ts:19-21`).
    let testCompressedPubkeyHex = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    var testCompressedPubkey: Data { Data(hexString: testCompressedPubkeyHex)! }

    // MARK: - computeAddressHash

    func testAddressHashEcdsaIsHash160() throws {
        let result = try QBTCClaimHashes.computeAddressHash(
            compressedPubkey: testCompressedPubkey,
            circuit: .ecdsa
        )
        let expected = Hash.ripemd(data: Hash.sha256(data: testCompressedPubkey))
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.count, 20)
    }

    func testAddressHashSchnorrIsXOnly() throws {
        let result = try QBTCClaimHashes.computeAddressHash(
            compressedPubkey: testCompressedPubkey,
            circuit: .schnorr
        )
        let expected = testCompressedPubkey.subdata(in: 1..<33)
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.count, 32)
    }

    func testAddressHashRejectsWrongLengthPubkey() {
        let tooShort = Data(repeating: 0x02, count: 32)
        XCTAssertThrowsError(try QBTCClaimHashes.computeAddressHash(
            compressedPubkey: tooShort,
            circuit: .ecdsa
        ))
    }

    func testAddressHashRejectsBadPrefixByte() {
        var bad = testCompressedPubkey
        bad[0] = 0x04 // uncompressed-form prefix; not allowed
        XCTAssertThrowsError(try QBTCClaimHashes.computeAddressHash(
            compressedPubkey: bad,
            circuit: .ecdsa
        ))
    }

    // MARK: - computeQbtcAddressHash

    func testQbtcAddressHashIsSha256OfUtf8() throws {
        let qbtcAddress = "qbtc1abc123"
        let result = try QBTCClaimHashes.computeQbtcAddressHash(qbtcAddress)
        let expected = Hash.sha256(data: qbtcAddress.data(using: .utf8)!)
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.count, 32)
    }

    // MARK: - computeChainIdHash

    func testChainIdHashIsFirst8BytesOfSha256() throws {
        let result = try QBTCClaimHashes.computeChainIdHash("qbtc-1")
        let full = Hash.sha256(data: "qbtc-1".data(using: .utf8)!)
        XCTAssertEqual(result, full.prefix(8))
        XCTAssertEqual(result.count, 8)
    }

    // MARK: - computeClaimMessageHash

    func testClaimMessageHashEcdsa() throws {
        let addressHash = Data(repeating: 0xaa, count: 20)
        let qbtcAddressHash = Data(repeating: 0xbb, count: 32)
        let chainIdHash = Data(repeating: 0xcc, count: 8)

        let result = try QBTCClaimHashes.computeClaimMessageHash(
            addressHash: addressHash,
            qbtcAddressHash: qbtcAddressHash,
            chainIdHash: chainIdHash,
            circuit: .ecdsa
        )

        XCTAssertEqual(result.count, 32)

        // Manually construct the same input — the prefix MUST be
        // exactly "ecdsa-hash160:" and the suffix exactly "qbtc-claim-v1",
        // matching ClaimTagECDSAHash160 on the chain side.
        var input = Data()
        input.append("ecdsa-hash160:".data(using: .utf8)!)
        input.append(addressHash)
        input.append(qbtcAddressHash)
        input.append(chainIdHash)
        input.append("qbtc-claim-v1".data(using: .utf8)!)

        XCTAssertEqual(result, Hash.sha256(data: input))
    }

    func testClaimMessageHashRejectsSchnorr() {
        let addressHash = Data(repeating: 0xaa, count: 32)
        let qbtcAddressHash = Data(repeating: 0xbb, count: 32)
        let chainIdHash = Data(repeating: 0xcc, count: 8)

        XCTAssertThrowsError(try QBTCClaimHashes.computeClaimMessageHash(
            addressHash: addressHash,
            qbtcAddressHash: qbtcAddressHash,
            chainIdHash: chainIdHash,
            circuit: .schnorr
        )) { error in
            guard let err = error as? QBTCClaimHashError, case .schnorrNotSupported = err else {
                return XCTFail("expected schnorrNotSupported, got \(error)")
            }
        }
    }

    func testClaimMessageHashRejectsWrongLengthInputs() {
        let bad20 = Data(repeating: 0xaa, count: 19)
        let qbtcAddressHash = Data(repeating: 0xbb, count: 32)
        let chainIdHash = Data(repeating: 0xcc, count: 8)
        XCTAssertThrowsError(try QBTCClaimHashes.computeClaimMessageHash(
            addressHash: bad20,
            qbtcAddressHash: qbtcAddressHash,
            chainIdHash: chainIdHash,
            circuit: .ecdsa
        ))
    }

    // MARK: - computeAll

    func testComputeAllForP2wpkh() throws {
        let result = try QBTCClaimHashes.computeAll(
            btcAddress: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
            compressedPubkey: testCompressedPubkey,
            qbtcAddress: "qbtc1test",
            chainId: "qbtc-1"
        )

        XCTAssertEqual(result.circuit, .ecdsa)
        XCTAssertEqual(result.addressHash.count, 20)
        XCTAssertEqual(result.qbtcAddressHash.count, 32)
        XCTAssertEqual(result.messageHash.count, 32)
    }

    func testComputeAllRejectsP2trUntilSchnorrTagDefined() {
        XCTAssertThrowsError(try QBTCClaimHashes.computeAll(
            btcAddress: "bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297",
            compressedPubkey: testCompressedPubkey,
            qbtcAddress: "qbtc1test",
            chainId: "qbtc-1"
        )) { error in
            guard let err = error as? QBTCClaimHashError, case .schnorrNotSupported = err else {
                return XCTFail("expected schnorrNotSupported, got \(error)")
            }
        }
    }

    // MARK: - BtcAddressType detection (covers §1.2)

    func testDetectAddressTypes() throws {
        XCTAssertEqual(try BtcAddressType.detect("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"), .p2pkh)
        XCTAssertEqual(try BtcAddressType.detect("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"), .p2shP2wpkh)
        XCTAssertEqual(try BtcAddressType.detect("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"), .p2wpkh)
        XCTAssertEqual(try BtcAddressType.detect("bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297"), .p2tr)
    }

    func testDetectRejectsTestnet() {
        XCTAssertThrowsError(try BtcAddressType.detect("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx")) { error in
            guard let err = error as? BtcAddressTypeError, case .testnetNotSupported = err else {
                return XCTFail("expected testnetNotSupported, got \(error)")
            }
        }
    }

    func testDetectRejectsUnknownPrefix() {
        XCTAssertThrowsError(try BtcAddressType.detect("xyz123"))
    }
}
