//
//  RippleXAddressTests.swift
//  VultisigAppTests
//
//  Pins the hand-rolled XLS-5d X-address codec against the canonical
//  vectors published in xrpl.js `ripple-address-codec` (test/index.test.ts),
//  covering tag-present / tag-absent / tag-zero, the testnet prefix, the
//  reserved 64-bit-tag flag, and checksum corruption. WalletCore validation
//  is cross-checked so the codec can't drift from what the signer accepts.
//

import WalletCore
import XCTest
@testable import VultisigApp

final class RippleXAddressTests: XCTestCase {

    /// Canonical (classicAddress, tag, mainnet X-address) vectors from
    /// xrpl.js ripple-address-codec.
    private let vectors: [(classic: String, tag: UInt32?, xAddress: String)] = [
        ("r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59", nil, "X7AcgcsBL6XDcUb289X4mJ8djcdyKaB5hJDWMArnXr61cqZ"),
        ("r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59", 1, "X7AcgcsBL6XDcUb289X4mJ8djcdyKaGZMhc9YTE92ehJ2Fu"),
        ("r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59", 11747, "X7AcgcsBL6XDcUb289X4mJ8djcdyKaLFuhLRuNXPrDeJd9A"),
        ("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf", nil, "XVLhHMPHU98es4dbozjVtdWzVrDjtV5fdx1mHp98tDMoQXb"),
        ("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf", 0, "XVLhHMPHU98es4dbozjVtdWzVrDjtV8AqEL4xcZj5whKbmc"),
        ("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf", 16781933, "XVLhHMPHU98es4dbozjVtdWzVrDjtVqrDUk2vDpkTjPsY73"),
        ("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf", 4294967295, "XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHi"),
        ("rsA2LpzuawewSBQXkiju3YQTMzW13pAAdW", 23480, "X7d3eHCXzwBeWrZec1yT24iZerQjYL8m8zCJ16ACxu1BrBY")
    ]

    // MARK: - Decoding canonical vectors

    func testDecodeMainnetXAddressWithTag() throws {
        let decoded = try RippleXAddress.decode("X7AcgcsBL6XDcUb289X4mJ8djcdyKaGZMhc9YTE92ehJ2Fu")
        XCTAssertEqual(decoded.classicAddress, "r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59")
        XCTAssertEqual(decoded.tag, 1)
    }

    func testDecodeXAddressWithoutTag() throws {
        let decoded = try RippleXAddress.decode("X7AcgcsBL6XDcUb289X4mJ8djcdyKaB5hJDWMArnXr61cqZ")
        XCTAssertEqual(decoded.classicAddress, "r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59")
        XCTAssertNil(decoded.tag)
    }

    func testDecodeTagZeroDistinctFromNoTag() throws {
        let tagged = try RippleXAddress.decode("XVLhHMPHU98es4dbozjVtdWzVrDjtV8AqEL4xcZj5whKbmc")
        XCTAssertEqual(tagged.tag, 0, "Tag 0 is a real tag")

        let untagged = try RippleXAddress.decode("XVLhHMPHU98es4dbozjVtdWzVrDjtV5fdx1mHp98tDMoQXb")
        XCTAssertNil(untagged.tag, "No-tag flag decodes as nil, not 0")

        XCTAssertEqual(tagged.classicAddress, untagged.classicAddress)
    }

    func testDecodeMaxU32Tag() throws {
        let decoded = try RippleXAddress.decode("XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHi")
        XCTAssertEqual(decoded.classicAddress, "rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf")
        XCTAssertEqual(decoded.tag, UInt32.max)
    }

    func testClassicEncodeRoundTripForAllVectors() throws {
        for vector in vectors {
            let decoded = try RippleXAddress.decode(vector.xAddress)
            XCTAssertEqual(decoded.classicAddress, vector.classic, "classic mismatch for \(vector.xAddress)")
            XCTAssertEqual(decoded.tag, vector.tag, "tag mismatch for \(vector.xAddress)")
        }
    }

    // MARK: - Rejections

    func testRejectTestnetTAddress() {
        XCTAssertThrowsError(try RippleXAddress.decode("TVE26TYGhfLC7tQDno7G8dGtxSkYQn49b3qD26PK7FcGSKE")) { error in
            XCTAssertEqual(error as? RippleXAddress.DecodeError, .testnetAddress)
        }
    }

    func testRejectCorruptedChecksum() {
        // Last character of the untagged rGWr... vector flipped (b → a).
        XCTAssertThrowsError(try RippleXAddress.decode("XVLhHMPHU98es4dbozjVtdWzVrDjtV5fdx1mHp98tDMoQXa")) { error in
            XCTAssertEqual(error as? RippleXAddress.DecodeError, .notAnXAddress)
        }
    }

    func testReject64BitTagFlag() {
        // Canonical xrpl.js "Unsupported X-address" vector: flag byte 2,
        // encoded from tag UInt32.max + 1.
        XCTAssertThrowsError(try RippleXAddress.decode("XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8zeUygYrCgrPh")) { error in
            XCTAssertEqual(error as? RippleXAddress.DecodeError, .unsupportedTag)
        }
    }

    func testRejectBadPrefix() {
        // Canonical xrpl.js "bad prefix" vector: valid checksum, unknown prefix.
        XCTAssertThrowsError(try RippleXAddress.decode("dGzKGt8CVpWoa8aWL1k18tAdy9Won3PxynvbbpkAqp3V47g")) { error in
            XCTAssertEqual(error as? RippleXAddress.DecodeError, .notAnXAddress)
        }
    }

    func testRejectClassicAddressInput() {
        // A classic r-address is valid base58check but its payload is
        // 21 bytes, not the 31 of an X-address.
        XCTAssertThrowsError(try RippleXAddress.decode("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf")) { error in
            XCTAssertEqual(error as? RippleXAddress.DecodeError, .notAnXAddress)
        }
    }

    func testRejectGarbage() {
        for garbage in ["", "X", "hello world", "X0OIl", "XVLhHMPHU98es4dbozjVtdWzVrDjtV"] {
            XCTAssertThrowsError(try RippleXAddress.decode(garbage), "expected rejection for \(garbage)")
        }
    }

    // MARK: - WalletCore cross-check

    func testWalletCoreValidatesTheSameMainnetVectors() {
        // The signer resolves X-addresses internally; every mainnet vector
        // this codec accepts must also be a valid wallet-core XRP address,
        // and the decoded classic address must be too.
        for vector in vectors {
            XCTAssertTrue(CoinType.xrp.validate(address: vector.xAddress), "wallet-core rejected \(vector.xAddress)")
            XCTAssertTrue(CoinType.xrp.validate(address: vector.classic), "wallet-core rejected \(vector.classic)")
        }
    }
}
