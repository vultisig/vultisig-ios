//
//  HumanDecimalAmountTests.swift
//  VultisigAppTests
//
//  Four locale defects that a `NumberFormatter`-based parse ships, each of
//  which multiplies an amount rather than refusing it.
//
//  This is the union of two suites. The parser was written twice under two
//  names — `HumanDecimalAmount` for the LP and raw-memo forms, `SwitchAmount`
//  for the Cosmos SWITCH form — deliberately kept apart so the two migrations
//  would not conflict. They were the same algorithm, so the copies were
//  collapsed onto this one and both suites kept: each had found cases the other
//  had not. Three assertions from the SWITCH suite that restated a case already
//  here (the keypad states, a lone comma-decimal, and its junk set's overlap
//  with this one) were not carried over twice; its numeric-lookalike inputs
//  were, since they spell the rule differently.
//

import XCTest
@testable import VultisigApp

final class HumanDecimalAmountTests: XCTestCase {

    private let usa = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")
    private let india = Locale(identifier: "en_IN")
    /// ATOM's scale — what the SWITCH form parses against, and small enough
    /// that a truncation case is visible in a short literal.
    private static let atomDecimals = 6

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
    ///
    /// The last two come from the SWITCH suite: a leading zero group is refused
    /// wherever it appears, including ahead of a legitimate decimal part.
    func testALeadingZeroGroupIsRefused() {
        XCTAssertNil(parse("0,500", locale: usa))
        XCTAssertNil(parse("0.500", locale: germany))
        XCTAssertNil(parse("0,500.25", locale: usa))
        XCTAssertNil(parse("01,234", locale: usa))
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
        // The SWITCH suite's own spellings: a lookalike appended to a real
        // digit, and a vulgar fraction alone.
        XCTAssertNil(parse("1\u{00B2}", locale: usa))
        XCTAssertNil(parse("\u{215B}", locale: usa))
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

    // MARK: - Carried over from the SWITCH suite

    func testWholeAndFractionalAmounts() {
        XCTAssertEqual(parse("1", locale: usa), Decimal(string: "1"))
        XCTAssertEqual(parse("0.000001", decimals: Self.atomDecimals, locale: usa), Decimal(string: "0.000001"))
        XCTAssertEqual(parse("0", locale: usa), .zero)
    }

    /// Precision past the asset's own scale is dropped, not rounded. Rounding up
    /// at the balance ceiling would build a transfer of more than the wallet
    /// holds; rounding down can only leave dust behind.
    func testPrecisionPastTheAssetsScaleIsTruncated() {
        XCTAssertEqual(parse("1.0000009", decimals: Self.atomDecimals, locale: usa), Decimal(string: "1"))
        XCTAssertEqual(parse("1.1234569", decimals: Self.atomDecimals, locale: usa), Decimal(string: "1.123456"))
        XCTAssertEqual(parse("0.0000009", decimals: Self.atomDecimals, locale: usa), .zero)
    }

    /// `Decimal.formatToDecimal(digits:)` — what the percentage buttons write
    /// into the field — emits grouping separators, including several groups.
    func testGroupedInputIsAccepted() {
        XCTAssertEqual(parse("12,345.5", locale: usa), Decimal(string: "12345.5"))
        XCTAssertEqual(parse("12.345,5", locale: germany), Decimal(string: "12345.5"))
        XCTAssertEqual(parse("1,234,567", locale: usa), Decimal(string: "1234567"))
    }

    /// The hazard the strict grouping check exists for, in the shapes a width
    /// check alone would let through.
    func testAnAmountWrittenInTheOtherLocalesConventionIsRefusedNotReinterpreted() {
        XCTAssertNil(parse("1,5", locale: usa))
        XCTAssertNil(parse("1.5", locale: germany))
        XCTAssertNil(parse("12,34", locale: usa))
        XCTAssertNil(parse("1,23456", locale: usa))
    }

    /// Grouping is only grouping where the digits are actually grouped: a first
    /// group of one to three digits, every later group of exactly three.
    func testMalformedGroupingIsRefused() {
        XCTAssertNil(parse("1,2345", locale: usa))
        XCTAssertNil(parse("1234,56.5", locale: usa))
        XCTAssertNil(parse(",5", locale: usa))
        XCTAssertNil(parse("1,", locale: usa))
        XCTAssertNil(parse("1 5", locale: usa))
        XCTAssertNil(parse("1'5", locale: usa))
        XCTAssertNil(parse("1,50", locale: usa))
        XCTAssertNil(parse("1.50", locale: germany))
    }

    /// The grouping widths come from the locale, not from a hard-coded three:
    /// the field is filled by a formatter reading the same locale, so a rule
    /// that only knew about thousands separators would refuse an Indian-region
    /// user their own "max" amount.
    func testIndianGroupingIsAcceptedWhereTheLocaleUsesIt() throws {
        let hindi = Locale(identifier: "hi_IN")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = hindi
        try XCTSkipUnless(
            formatter.secondaryGroupingSize == 2,
            "Foundation on this OS does not report hi_IN's secondary grouping size"
        )

        XCTAssertEqual(parse("12,34,567", locale: hindi), Decimal(string: "1234567"))
        XCTAssertEqual(parse("12,345", locale: hindi), Decimal(string: "12345"))
        XCTAssertNil(parse("12,345,67", locale: hindi))
        // Not how 123456 is written there — far more likely a comma-decimal
        // `123.456` pasted in, which stripping the separator would turn into a
        // thousand-times send.
        XCTAssertNil(parse("123,456", locale: hindi))
    }

    /// The round trip the single-character non-Latin case cannot cover: a real
    /// amount formatted by the locale's own formatter has to read back.
    func testAnAmountInTheLocalesOwnDigitsIsAccepted() throws {
        let egypt = Locale(identifier: "ar_EG")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = egypt
        formatter.maximumFractionDigits = Self.atomDecimals

        let original = try XCTUnwrap(Decimal(string: "1234.5"))
        let text = try XCTUnwrap(formatter.string(from: NSDecimalNumber(decimal: original)))
        try XCTSkipUnless(
            text.contains { !$0.isASCII },
            "Foundation on this OS formats ar_EG with ASCII digits"
        )

        XCTAssertEqual(parse(text, decimals: Self.atomDecimals, locale: egypt), original)
    }

    func testJunkIsRejected() {
        XCTAssertNil(parse("   ", locale: usa))
        XCTAssertNil(parse("1e6", locale: usa))
        XCTAssertNil(parse("+1", locale: usa))
    }

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
            let formatted = original.formatToDecimal(digits: Self.atomDecimals)
            XCTAssertEqual(
                parse(formatted, decimals: Self.atomDecimals, locale: .current),
                original,
                "\(formatted) must read back as \(original)"
            )
        }
    }
}
