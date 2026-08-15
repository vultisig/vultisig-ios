//
//  UnmergeSharesTests.swift
//  VultisigAppTests
//
//  The human-decimal → base-unit conversion the unmerge memo is built from.
//  This is the layer the legacy path lost digits in — twice, once parsing
//  (`NumberFormatter` hands back a `Double`-backed `NSNumber`) and once
//  formatting (`String(format: "%.0f", …doubleValue)`).
//

import BigInt
@testable import VultisigApp
import XCTest

final class UnmergeSharesTests: XCTestCase {

    private static let us = Locale(identifier: "en_US")
    private static let de = Locale(identifier: "de_DE")

    // MARK: - Exactness

    /// The whole point of the migration. `123456789.12345679` shares is
    /// `12345678912345679` base units — 17 digits, which is past the ~15–16 a
    /// `Double` can hold exactly, so the legacy conversion lands on a different
    /// integer and withdraws a different amount.
    func testLargeShareCountSurvivesExactly() {
        XCTAssertEqual(
            UnmergeShares.parse("123456789.12345679", locale: Self.us),
            BigInt("12345678912345679")
        )
    }

    /// Guards the assumption above rather than asserting it in prose: the
    /// legacy Decimal → Double → `%.0f` pipeline really does answer something
    /// else for the same input.
    func testTheLegacyDoublePipelineDisagreesOnThatShareCount() {
        let raw = Decimal(string: "123456789.12345679")! * pow(Decimal(10), 8)
        let legacy = String(format: "%.0f", NSDecimalNumber(decimal: raw).doubleValue)
        XCTAssertNotEqual(legacy, "12345678912345679")
    }

    func testWholeAndFractionalAmounts() {
        XCTAssertEqual(UnmergeShares.parse("1", locale: Self.us), BigInt(100_000_000))
        XCTAssertEqual(UnmergeShares.parse("1.5", locale: Self.us), BigInt(150_000_000))
        XCTAssertEqual(UnmergeShares.parse("0.00000001", locale: Self.us), BigInt(1))
    }

    // MARK: - Truncation

    /// Sub-base-unit precision is dropped, not rounded. Legacy's `%.0f` rounded
    /// `1.5` raw shares up to `2`, which can ask for more shares than the merge
    /// account holds when the amount was typed at the exact balance.
    func testSubBaseUnitPrecisionIsTruncatedNotRounded() {
        XCTAssertEqual(UnmergeShares.parse("0.000000014", locale: Self.us), BigInt(1))
        XCTAssertEqual(UnmergeShares.parse("0.000000015", locale: Self.us), BigInt(1))
        XCTAssertEqual(UnmergeShares.parse("0.000000019", locale: Self.us), BigInt(1))
        XCTAssertEqual(UnmergeShares.parse("0.000000004", locale: Self.us), BigInt.zero)
    }

    // MARK: - Locale shapes

    /// `Decimal.formatToDecimal(digits:)` — what the percentage buttons write
    /// into the field — emits grouping separators.
    func testGroupedInputIsAccepted() {
        XCTAssertEqual(UnmergeShares.parse("12,345.5", locale: Self.us), BigInt("1234550000000"))
        XCTAssertEqual(UnmergeShares.parse("12.345,5", locale: Self.de), BigInt("1234550000000"))
    }

    func testCommaDecimalSeparator() {
        XCTAssertEqual(UnmergeShares.parse("1,5", locale: Self.de), BigInt(150_000_000))
    }

    /// The hazard the strict grouping check exists for. `NumberFormatter` reads
    /// `1,5` in `en_US` as fifteen and `1.5` in `de_DE` the same way, and a
    /// parser that simply strips the grouping separator agrees with it — so an
    /// amount pasted in the other convention would withdraw ten times what was
    /// asked for. Both are refused.
    func testAnAmountWrittenInTheOtherLocalesConventionIsRefusedNotReinterpreted() {
        XCTAssertNil(UnmergeShares.parse("1,5", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("1.5", locale: Self.de))
        XCTAssertNil(UnmergeShares.parse("12,34", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("1,23456", locale: Self.us))
    }

    /// Grouping is only grouping where the digits are actually grouped: the
    /// first group of one to three digits, every later group of exactly three.
    func testMalformedGroupingIsRefused() {
        XCTAssertNil(UnmergeShares.parse("1,2345", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("1234,56.5", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse(",5", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("1,", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("1 5", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("1'5", locale: Self.us))
    }

    func testWellFormedGroupingIsAccepted() {
        XCTAssertEqual(UnmergeShares.parse("1,234,567", locale: Self.us), BigInt("123456700000000"))
        XCTAssertEqual(UnmergeShares.parse("123,456", locale: Self.us), BigInt("12345600000000"))
        XCTAssertEqual(UnmergeShares.parse("1234567", locale: Self.us), BigInt("123456700000000"))
    }

    /// The keypad's mid-entry states are numbers, not junk.
    func testPartialKeypadStates() {
        XCTAssertEqual(UnmergeShares.parse(".5", locale: Self.us), BigInt(50_000_000))
        XCTAssertEqual(UnmergeShares.parse("5.", locale: Self.us), BigInt(500_000_000))
    }

    // MARK: - Rejection

    /// A share count that cannot be read exactly is refused rather than coerced
    /// — a coerced one is a silently wrong withdrawal.
    func testJunkIsRejected() {
        XCTAssertNil(UnmergeShares.parse("", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("   ", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("abc", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("1.2.3", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("-1", locale: Self.us))
        XCTAssertNil(UnmergeShares.parse("1e8", locale: Self.us))
    }

    // MARK: - Back to a decimal

    func testDecimalValueRoundTrips() {
        XCTAssertEqual(UnmergeShares.decimalValue(of: BigInt(150_000_000)), Decimal(string: "1.5"))
        XCTAssertEqual(UnmergeShares.decimalValue(of: .zero), .zero)
        XCTAssertEqual(
            UnmergeShares.decimalValue(of: BigInt("12345678912345679")),
            Decimal(string: "123456789.12345679")
        )
    }
}
