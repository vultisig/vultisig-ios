//
//  HumanDecimalAmountTests.swift
//  VultisigAppTests
//
//  The human-decimal parse a form's amount field is read through. An amount
//  reinterpreted under the wrong separator convention is a ten-times send from
//  a paste, which is why the parser refuses ambiguity instead of guessing —
//  and why these cases are carried alongside the algorithm rather than
//  re-derived.
//

@testable import VultisigApp
import Foundation
import XCTest

final class HumanDecimalAmountTests: XCTestCase {

    private static let us = Locale(identifier: "en_US")
    private static let de = Locale(identifier: "de_DE")
    private static let fixtureDecimals = 6

    private func parse(
        _ text: String,
        decimals: Int = HumanDecimalAmountTests.fixtureDecimals,
        locale: Locale
    ) -> Decimal? {
        HumanDecimalAmount.parse(text, decimals: decimals, locale: locale)
    }

    // MARK: - Plain amounts

    func testWholeAndFractionalAmounts() {
        XCTAssertEqual(parse("1", locale: Self.us), Decimal(string: "1"))
        XCTAssertEqual(parse("1.5", locale: Self.us), Decimal(string: "1.5"))
        XCTAssertEqual(parse("0.000001", locale: Self.us), Decimal(string: "0.000001"))
        XCTAssertEqual(parse("0", locale: Self.us), .zero)
    }

    /// The keypad's mid-entry states are numbers, not junk.
    func testPartialKeypadStates() {
        XCTAssertEqual(parse(".5", locale: Self.us), Decimal(string: "0.5"))
        XCTAssertEqual(parse("5.", locale: Self.us), Decimal(string: "5"))
    }

    // MARK: - Truncation

    /// Precision past the asset's own scale is dropped, not rounded. Rounding up
    /// at the balance ceiling would build a transfer of more than the wallet
    /// holds; rounding down can only leave dust behind.
    func testPrecisionPastTheAssetsScaleIsTruncated() {
        XCTAssertEqual(parse("1.0000009", locale: Self.us), Decimal(string: "1"))
        XCTAssertEqual(parse("1.1234569", locale: Self.us), Decimal(string: "1.123456"))
        XCTAssertEqual(parse("0.0000009", locale: Self.us), .zero)
    }

    /// An 18-decimal asset is where a `Double`-backed parse would start losing
    /// significant digits; `Decimal` must keep every one of them.
    func testAnEighteenDecimalAmountKeepsEveryDigit() {
        XCTAssertEqual(
            parse("1.234567890123456789", decimals: 18, locale: Self.us),
            Decimal(string: "1.234567890123456789")
        )
    }

    // MARK: - Locale shapes

    /// `Decimal.formatToDecimal(digits:)` — what the percentage buttons write
    /// into the field — emits grouping separators.
    func testGroupedInputIsAccepted() {
        XCTAssertEqual(parse("12,345.5", locale: Self.us), Decimal(string: "12345.5"))
        XCTAssertEqual(parse("12.345,5", locale: Self.de), Decimal(string: "12345.5"))
        XCTAssertEqual(parse("1,234,567", locale: Self.us), Decimal(string: "1234567"))
    }

    func testCommaDecimalSeparator() {
        XCTAssertEqual(parse("1,5", locale: Self.de), Decimal(string: "1.5"))
    }

    /// The hazard the strict grouping check exists for. `NumberFormatter` — and
    /// therefore the shared `String.parseInput()` — reads `1,5` in `en_US` as
    /// fifteen and `1.5` in `de_DE` the same way. On this path that is a
    /// ten-times deposit from a paste, so both are refused and the form says
    /// the amount is invalid.
    func testAnAmountWrittenInTheOtherLocalesConventionIsRefusedNotReinterpreted() {
        XCTAssertNil(parse("1,5", locale: Self.us))
        XCTAssertNil(parse("1.5", locale: Self.de))
        XCTAssertNil(parse("12,34", locale: Self.us))
        XCTAssertNil(parse("1,23456", locale: Self.us))
    }

    /// The same hazard in the one shape that passes a width check: `0,500` has
    /// the group widths a grouped `en_US` number would have, but nobody writes
    /// five hundred that way — it is half, written comma-decimal, and stripping
    /// the separator would send five hundred times the intended amount.
    func testALeadingZeroGroupIsRefused() {
        XCTAssertNil(parse("0,500", locale: Self.us))
        XCTAssertNil(parse("0.500", locale: Self.de))
        XCTAssertNil(parse("0,500.25", locale: Self.us))
        XCTAssertNil(parse("01,234", locale: Self.us))
    }

    /// Grouping is only grouping where the digits are actually grouped: a first
    /// group of one to three digits, every later group of exactly three.
    func testMalformedGroupingIsRefused() {
        XCTAssertNil(parse("1,2345", locale: Self.us))
        XCTAssertNil(parse("1234,56.5", locale: Self.us))
        XCTAssertNil(parse(",5", locale: Self.us))
        XCTAssertNil(parse("1,", locale: Self.us))
        XCTAssertNil(parse("1 5", locale: Self.us))
        XCTAssertNil(parse("1'5", locale: Self.us))
        XCTAssertNil(parse("1,50", locale: Self.us))
        XCTAssertNil(parse("1.50", locale: Self.de))
    }

    /// The grouping widths come from the locale, not from a hard-coded three:
    /// the field is filled by a formatter reading the same locale, so a rule
    /// that only knew about thousands separators would refuse an Indian-region
    /// user their own "max" amount.
    func testIndianGroupingIsAcceptedWhereTheLocaleUsesIt() throws {
        let india = Locale(identifier: "hi_IN")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = india
        try XCTSkipUnless(
            formatter.secondaryGroupingSize == 2,
            "Foundation on this OS does not report hi_IN's secondary grouping size"
        )

        XCTAssertEqual(parse("12,34,567", locale: india), Decimal(string: "1234567"))
        XCTAssertEqual(parse("12,345", locale: india), Decimal(string: "12345"))
        XCTAssertNil(parse("12,345,67", locale: india))
        // Not how 123456 is written there — far more likely a comma-decimal
        // `123.456` pasted in, which stripping the separator would turn into a
        // thousand-times deposit.
        XCTAssertNil(parse("123,456", locale: india))
    }

    /// A locale's numbering system may be non-Latin, and the formatter that
    /// fills this field emits whatever digits that locale uses. Refusing them
    /// would leave those users unable to submit their own "max" amount.
    func testAnAmountInTheLocalesOwnDigitsIsAccepted() throws {
        let egypt = Locale(identifier: "ar_EG")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = egypt
        formatter.maximumFractionDigits = Self.fixtureDecimals

        let original = try XCTUnwrap(Decimal(string: "1234.5"))
        let text = try XCTUnwrap(formatter.string(from: NSDecimalNumber(decimal: original)))
        try XCTSkipUnless(
            text.contains { !$0.isASCII },
            "Foundation on this OS formats ar_EG with ASCII digits"
        )

        XCTAssertEqual(HumanDecimalAmount.parse(text, decimals: Self.fixtureDecimals, locale: egypt), original)
    }

    /// Digits only — not every character Unicode gives a numeric value to. A
    /// superscript or a Roman numeral folding into a digit would silently change
    /// the amount.
    func testNonDecimalNumericCharactersAreRefused() {
        XCTAssertNil(parse("1\u{00B2}", locale: Self.us))
        XCTAssertNil(parse("\u{215B}", locale: Self.us))
        XCTAssertNil(parse("\u{216B}", locale: Self.us))
    }

    // MARK: - Rejection

    func testJunkIsRejected() {
        XCTAssertNil(parse("", locale: Self.us))
        XCTAssertNil(parse("   ", locale: Self.us))
        XCTAssertNil(parse("abc", locale: Self.us))
        XCTAssertNil(parse("1.2.3", locale: Self.us))
        XCTAssertNil(parse("-1", locale: Self.us))
        XCTAssertNil(parse("1e6", locale: Self.us))
        XCTAssertNil(parse("+1", locale: Self.us))
    }

    // MARK: - Round trip through the app's own formatter

    /// The percentage buttons write `Decimal.formatToDecimal(digits:)` into the
    /// field, and the builder writes the same formatter's output into the
    /// transaction. Parser and formatter have to agree about the machine's own
    /// locale or "max" silently means something else — so this one runs in
    /// `.current` on purpose.
    func testTheFormattersOutputParsesBackToTheSameValue() {
        for value in ["1", "1.5", "12345.678901", "0.000001"] {
            guard let original = Decimal(string: value) else {
                return XCTFail("Bad fixture \(value)")
            }
            let formatted = original.formatToDecimal(digits: Self.fixtureDecimals)
            XCTAssertEqual(
                HumanDecimalAmount.parse(formatted, decimals: Self.fixtureDecimals, locale: .current),
                original,
                "\(formatted) must read back as \(original)"
            )
        }
    }
}
