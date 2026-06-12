//
//  ZcashServiceTests.swift
//  VultisigAppTests
//
//  Pins the ZIP-243 branch-id byte-reversal: the Zcash node reports
//  `consensus.nextblock` big-endian, but WalletCore reads it little-endian off
//  the plan. Getting this wrong yields a digest the network rejects.
//

import XCTest
@testable import VultisigApp

final class ZcashServiceTests: XCTestCase {

    func testReversesBigEndianNextblockToLittleEndian() {
        XCTAssertEqual(ZcashService.reverseHexBytes("5437f330"), "30f33754")
    }

    func testLowercasesUppercaseHex() {
        XCTAssertEqual(ZcashService.reverseHexBytes("5437F330"), "30f33754")
    }

    func testReturnsNilForNonHexValue() {
        XCTAssertNil(ZcashService.reverseHexBytes("not-hex!"))
    }

    func testReturnsNilForWrongByteLength() {
        XCTAssertNil(ZcashService.reverseHexBytes("5437f3"))
        XCTAssertNil(ZcashService.reverseHexBytes("5437f33042"))
    }

    func testReturnsNilForEmptyString() {
        XCTAssertNil(ZcashService.reverseHexBytes(""))
    }
}
