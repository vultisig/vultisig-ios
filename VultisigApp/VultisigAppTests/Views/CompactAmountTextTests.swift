//
//  CompactAmountTextTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class CompactAmountTextTests: XCTestCase {

    func testSegmentsSplitsSubscriptRunFromFormattedPrice() {
        XCTAssertEqual(
            CompactAmountText.segments(for: "$0.0₄1234"),
            [.plain("$0.0"), .zeroCount("4"), .plain("1234")]
        )
    }

    func testSegmentsConvertsMultiDigitSubscriptCount() {
        XCTAssertEqual(
            CompactAmountText.segments(for: "$0.0₁₁1"),
            [.plain("$0.0"), .zeroCount("11"), .plain("1")]
        )
    }

    func testSegmentsPassesPlainPriceThroughUntouched() {
        XCTAssertEqual(CompactAmountText.segments(for: "$1.23"), [.plain("$1.23")])
    }

    func testSegmentsHandlesSingleDigitSignificand() {
        XCTAssertEqual(
            CompactAmountText.segments(for: "$0.0₇3"),
            [.plain("$0.0"), .zeroCount("7"), .plain("3")]
        )
    }
}
