//
//  ThorchainAdvancedSwapQueueMimirTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Pure parsing of the `EnableAdvSwapQueue` mimir body. The gate must fail
/// CLOSED: only a live, confirmed `1` unblocks placement of a resting `=<`
/// order — every other value (disabled, market-only, unset, garbage) blocks.
final class ThorchainAdvancedSwapQueueMimirTests: XCTestCase {

    private func parse(_ body: String) -> Bool {
        ThorchainService.parseMimirEnabled(Data(body.utf8))
    }

    func testEnabledWhenBodyIsOne() {
        XCTAssertTrue(parse("1"))
    }

    func testEnabledToleratesSurroundingWhitespaceAndNewline() {
        XCTAssertTrue(parse(" 1\n"))
        XCTAssertTrue(parse("\t1\r\n"))
    }

    func testDisabledWhenValueIsQuoted() {
        // The real endpoint returns a bare `1`, never `"1"`. A quoted value is an
        // unexpected shape, so fail CLOSED rather than accept it.
        XCTAssertFalse(parse("\"1\""))
        XCTAssertFalse(parse("'1'"))
    }

    func testDisabledForIntLenientVariants() {
        // Must not accept `Int`-parse-equivalent forms of 1.
        XCTAssertFalse(parse("+1"))
        XCTAssertFalse(parse("01"))
        XCTAssertFalse(parse("1 1"))
        XCTAssertFalse(parse("1.0"))
    }

    func testDisabledWhenBodyIsZero() {
        XCTAssertFalse(parse("0"))
    }

    func testDisabledWhenBodyIsTwoMarketOnly() {
        // `2` = market-only (limit silently skipped) → block.
        XCTAssertFalse(parse("2"))
    }

    func testDisabledWhenBodyIsMinusOneUnset() {
        XCTAssertFalse(parse("-1"))
    }

    func testDisabledWhenBodyIsEmpty() {
        XCTAssertFalse(parse(""))
    }

    func testDisabledWhenBodyIsUnparseable() {
        XCTAssertFalse(parse("enabled"))
        XCTAssertFalse(parse("1.0"))
        XCTAssertFalse(parse("true"))
    }

    func testMimirKeyMatchesProtocolConstant() {
        XCTAssertEqual(ThorchainService.advancedSwapQueueMimirKey, "EnableAdvSwapQueue")
    }
}
