//
//  HumanDecimalAmountTests.swift
//  VultisigAppTests
//
//  Four locale defects that a `NumberFormatter`-based parse ships, each of
//  which multiplies an amount rather than refusing it.
//

import XCTest
@testable import VultisigApp

final class HumanDecimalAmountTests: XCTestCase {

    private let usa = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")
    private let india = Locale(identifier: "en_IN")

    private func parse(_ text: String, decimals: Int = 8, locale: Locale) -> Decimal? {
        HumanDecimalAmount.parse(text, decimals: decimals, locale: locale)
    }

    // MARK: - The plain cases

    func testAPlainDecimalParsesInItsOwnConvention() {
        XCTAssertEqual(parse("1.5", locale: usa), Decimal(string: "1.5"))
        XCTAssertEqual(parse("1,5", locale: germany), Decimal(string: "1.5"))
        XCTAssertEqual(parse("12", locale: usa), 12)
    }

    /// Mid-entry keypad states a user passes through on the way to a number.
    func testPartialKeypadStatesParse() {
        XCTAssertEqual(parse("5.", locale: usa), 5)
        XCTAssertEqual(parse(".5", locale: usa), Decimal(string: "0.5"))
    }

    func testGroupedAmountsParseInTheirOwnConvention() {
        XCTAssertEqual(parse("1,234.5", locale: usa), Decimal(string: "1234.5"))
        XCTAssertEqual(parse("1.234,5", locale: germany), Decimal(string: "1234.5"))
    }

    // MARK: - The four defects

    /// ⚠️ `1,5` in `en_US` is someone writing a comma-decimal amount. A
    /// `NumberFormatter` reads it as fifteen — a ten-times send from a paste.
    func testACommaDecimalIsRefusedInADotDecimalLocale() {
        XCTAssertNil(parse("1,5", locale: usa))
    }

    /// ⚠️ The mirror: `1.5` in `de_DE`.
    func testADotDecimalIsRefusedInACommaDecimalLocale() {
        XCTAssertNil(parse("1.5", locale: germany))
    }

    /// ⚠️ `0,500` has the group widths a grouped `en_US` number would have, so
    /// a width check alone lets it through as five hundred. Nobody writes five
    /// hundred that way — it is half, in a comma-decimal convention.
    func testALeadingZeroGroupIsRefused() {
        XCTAssertNil(parse("0,500", locale: usa))
        XCTAssertNil(parse("0.500", locale: germany))
    }

    /// ⚠️ In the Indian system `123,456` is not how 123456 is written —
    /// `1,23,456` is. Treating it as grouped would multiply by a thousand.
    func testAnIndianTwoGroupAmountIsRefused() {
        XCTAssertNil(parse("123,456", locale: india))
        XCTAssertEqual(parse("1,23,456", locale: india), 123_456)
    }

    /// ⚠️ A locale's numbering system may be non-Latin, and the percentage
    /// buttons write whatever digits it uses into the field. Refusing them would
    /// leave those users unable to submit their own "max" amount.
    func testNonLatinDigitsParse() {
        XCTAssertEqual(parse("٥", locale: Locale(identifier: "ar_EG")), 5)
        XCTAssertEqual(parse("५", locale: Locale(identifier: "hi_IN")), 5)
    }

    /// Numeric-looking characters that are not positional digits carry values
    /// that would otherwise fold into the amount.
    func testNumericLookalikesAreRefused() {
        XCTAssertNil(parse("²", locale: usa))
        XCTAssertNil(parse("½", locale: usa))
        XCTAssertNil(parse("Ⅻ", locale: usa))
        XCTAssertNil(parse("1e3", locale: usa))
        XCTAssertNil(parse("-1", locale: usa))
        XCTAssertNil(parse("abc", locale: usa))
        XCTAssertNil(parse("", locale: usa))
        XCTAssertNil(parse("1.2.3", locale: usa))
    }

    // MARK: - Truncation

    /// ⚠️ Truncated, never rounded. This value is compared against the wallet
    /// balance, and rounding up at the ceiling would build a transfer of
    /// slightly more than the balance holds.
    func testExcessFractionDigitsAreTruncatedNotRounded() {
        XCTAssertEqual(parse("1.999", decimals: 2, locale: usa), Decimal(string: "1.99"))
        XCTAssertEqual(parse("0.00000001", decimals: 8, locale: usa), Decimal(string: "0.00000001"))
        XCTAssertEqual(parse("0.00000001", decimals: 4, locale: usa), 0)
    }

    /// An 18-decimal asset is where a `Double`-backed parse starts losing
    /// significant digits.
    func testAnEighteenDecimalAmountKeepsEveryDigit() {
        XCTAssertEqual(
            parse("1.234567890123456789", decimals: 18, locale: usa),
            Decimal(string: "1.234567890123456789")
        )
    }
}
