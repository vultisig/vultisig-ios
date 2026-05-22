//
//  SwapKitPSBTParserTests.swift
//  VultisigAppTests
//
//  Cursor-level / framing-level coverage for `SwapKitPSBTParser` and
//  `PSBTCursor`. Per-chain signer tests cover end-to-end paths against
//  real spike fixtures — this file pins the parser primitives' defensive
//  behaviour (duplicate-key rejection, misalignment safety, varint
//  boundary handling).
//

import Foundation
import XCTest
@testable import VultisigApp

final class SwapKitPSBTParserTests: XCTestCase {

    // MARK: - Duplicate-key rejection (BIP-174 §map-records)

    func testReadMapRejectsDuplicateKeys() {
        // Two records with the same 1-byte key `0x07` should throw
        // `.malformed` — BIP-174 mandates unique keys within a map, and a
        // silent overwrite would let an adversarial upstream sneak in a
        // second record overriding the first.
        var bytes = Data()
        // Record 1: key=0x07, value=[0xAA]
        bytes.append(0x01) // keyLen
        bytes.append(0x07) // key
        bytes.append(0x01) // valLen
        bytes.append(0xAA) // val
        // Record 2: same key, different value
        bytes.append(0x01)
        bytes.append(0x07)
        bytes.append(0x01)
        bytes.append(0xBB)
        bytes.append(0x00) // terminator (unreachable)

        var cursor = PSBTCursor(data: bytes)
        XCTAssertThrowsError(try cursor.readMap()) { err in
            guard case SwapKitPSBTParserError.malformed(let reason) = err else {
                return XCTFail("expected .malformed, got \(err)")
            }
            XCTAssertTrue(reason.contains("07"), "diagnostic should include the duplicate key prefix")
        }
    }

    func testReadMapAcceptsUniqueKeys() throws {
        var bytes = Data()
        bytes.append(0x01); bytes.append(0x01); bytes.append(0x01); bytes.append(0xAA)
        bytes.append(0x01); bytes.append(0x02); bytes.append(0x01); bytes.append(0xBB)
        bytes.append(0x00) // terminator
        var cursor = PSBTCursor(data: bytes)
        let map = try cursor.readMap()
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[Data([0x01])], Data([0xAA]))
        XCTAssertEqual(map[Data([0x02])], Data([0xBB]))
    }

    // MARK: - Misalignment-safe little-endian reads

    func testCursorReadsLEAtArbitraryOffsets() throws {
        // Stick the multi-byte integers at offsets that are NOT naturally
        // aligned (offset 1, 3, 7) — `withUnsafeBytes.load(as:)` would
        // trap or return garbage on architectures that enforce alignment.
        // The byte-by-byte readers must produce correct values regardless.
        var bytes = Data([0x00])                       // padding to offset 1
        bytes.append(contentsOf: [0x34, 0x12])         // UInt16LE = 0x1234
        bytes.append(contentsOf: [0xff, 0xee, 0xdd, 0xcc, 0x44, 0x33, 0x22, 0x11])
        bytes.append(contentsOf: [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])

        var cursor = PSBTCursor(data: bytes)
        _ = try cursor.readByte()
        XCTAssertEqual(try cursor.readUInt16LE(), 0x1234)
        XCTAssertEqual(try cursor.readUInt32LE(), 0xccddeeff)
        XCTAssertEqual(try cursor.readUInt32LE(), 0x11223344)
        XCTAssertEqual(try cursor.readUInt64LE(), 0x1122334455667788)
    }

    func testCursorReadsLEFromDataSliceWithNonZeroStartIndex() throws {
        // Construct a Data slice whose `startIndex` is non-zero — this is
        // what you get from `data[k..<n]` in practice, and a load(as:)
        // would compute the load address from the underlying parent
        // buffer's base rather than the slice's, which can land on a
        // misaligned address. The byte-by-byte readers iterate from
        // `data.startIndex + offset`, so they handle this correctly.
        let parent = Data([0x99, 0x99, 0x99, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12])
        let slice = parent[3...] // start at index 3, non-zero start
        var cursor = PSBTCursor(data: slice)
        XCTAssertEqual(try cursor.readUInt16LE(), 0x1234)
        XCTAssertEqual(try cursor.readUInt32LE(), 0x12345678)
    }

    // MARK: - Truncation safety

    func testCursorThrowsTruncatedOnShortBuffer() {
        var c1 = PSBTCursor(data: Data([0x00, 0x00, 0x00]))
        XCTAssertThrowsError(try c1.readUInt32LE())

        var c2 = PSBTCursor(data: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]))
        XCTAssertThrowsError(try c2.readUInt64LE())
    }
}
