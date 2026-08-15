//
//  IBCTransferAmountTests.swift
//  VultisigAppTests
//
//  The amount parse, with the locale injected — which locale is in force is the
//  behaviour under test, not an ambient property of the machine running it.
//
//  The case that matters: `NumberFormatter` reads `en_US` "1,5" as 15 and
//  `de_DE` "1.5" as 15, because a lone separator followed by one digit still
//  looks like grouping to it. On a transfer that is a ten-fold send from a
//  paste. Both must be REFUSED here, never reinterpreted.
//

@testable import VultisigApp
import XCTest

final class IBCTransferAmountTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")

    private func parse(_ text: String, locale: Locale, decimals: Int = 6) -> Decimal? {
        IBCTransferAmount.parse(text, decimals: decimals, locale: locale)
    }

    // MARK: - The 10x paste

    func testALoneSeparatorBeforeOneOrTwoDigitsIsRefusedNotRegrouped() {
        for text in ["1,5", "1,50", "12,5"] {
            XCTAssertNil(
                parse(text, locale: enUS),
                "en_US \(text) is a comma-decimal amount, not grouping — reinterpreting it sends 10x"
            )
        }

        for text in ["1.5", "1.50", "12.5"] {
            XCTAssertNil(
                parse(text, locale: deDE),
                "de_DE \(text) is a dot-decimal amount, not grouping — reinterpreting it sends 10x"
            )
        }
    }

    /// The other direction: each locale's own decimal separator works normally.
    func testEachLocaleReadsItsOwnDecimalSeparator() {
        XCTAssertEqual(parse("1.5", locale: enUS), Decimal(string: "1.5"))
        XCTAssertEqual(parse("1,5", locale: deDE), Decimal(string: "1.5"))
    }

    /// A single group boundary and nothing else to settle it is ambiguous in the
    /// most expensive direction: `1,000` is one thousand if the comma groups and
    /// *one* if it was written by someone whose decimal separator is a comma.
    /// Both readings are well-formed, so the string does not say which — and
    /// guessing wrong is a 1000× transfer.
    func testASingleGroupBoundaryWithNothingToDisambiguateItIsRefused() {
        for text in ["1,000", "1,234", "12,500", "100,000"] {
            XCTAssertNil(
                parse(text, locale: enUS),
                "en_US \(text) could be grouped or a comma-decimal amount — refusing is the only safe answer"
            )
        }

        for text in ["1.000", "1.234", "12.500"] {
            XCTAssertNil(parse(text, locale: deDE), "de_DE \(text) is ambiguous the same way")
        }
    }

    /// Grouping IS honoured once the string says unambiguously that it groups —
    /// either a second boundary (which cannot be a decimal point) or the decimal
    /// separator itself appearing alongside it.
    func testUnambiguousGroupingIsAccepted() {
        XCTAssertEqual(parse("1,234.5", locale: enUS), Decimal(string: "1234.5"))
        XCTAssertEqual(parse("1,000.0", locale: enUS), Decimal(1000))
        XCTAssertEqual(parse("12,345,678", locale: enUS), Decimal(12_345_678))

        XCTAssertEqual(parse("1.234,5", locale: deDE), Decimal(string: "1234.5"))
        XCTAssertEqual(parse("12.345.678", locale: deDE), Decimal(12_345_678))
    }

    func testMisplacedGroupingIsRefused() {
        for text in ["1,23", "1234,567", "1,2345", "12,34,567"] {
            XCTAssertNil(parse(text, locale: enUS), "en_US \(text) is not grouped where en_US groups")
        }
    }

    /// Ungrouped digits are never ambiguous, so the plain spelling of every
    /// refused amount above is accepted — which is what the user retypes.
    func testTheUngroupedSpellingIsAlwaysAccepted() {
        XCTAssertEqual(parse("1000", locale: enUS), Decimal(1000))
        XCTAssertEqual(parse("1000", locale: deDE), Decimal(1000))
        XCTAssertEqual(parse("12345678", locale: enUS), Decimal(12_345_678))
    }

    // MARK: - Shape

    func testPlainAndKeypadStates() {
        XCTAssertEqual(parse("0", locale: enUS), .zero)
        XCTAssertEqual(parse("5", locale: enUS), Decimal(5))
        XCTAssertEqual(parse("5.", locale: enUS), Decimal(5), "A trailing separator is a mid-entry keypad state")
        XCTAssertEqual(parse(".5", locale: enUS), Decimal(string: "0.5"), "A leading separator is too")
        XCTAssertEqual(parse("  1.5  ", locale: enUS), Decimal(string: "1.5"), "Surrounding whitespace is trimmed")
    }

    func testNonNumericInputIsRefused() {
        for text in ["", "   ", "abc", "1.2.3", "1e5", "-1", "1 5", "١٢٣"] {
            XCTAssertNil(parse(text, locale: enUS), "\(text.isEmpty ? "<empty>" : text) must be refused")
        }
    }

    /// Truncated, not rounded: rounding up an amount typed at the exact
    /// spendable balance would put it over the balance it was measured against.
    func testFractionDigitsPastTheCoinsScaleAreTruncated() {
        XCTAssertEqual(
            parse("1.9999999", locale: enUS, decimals: 6),
            Decimal(string: "1.999999"),
            "The seventh digit is dropped, not rounded up"
        )
        XCTAssertEqual(parse("1.123456789", locale: enUS, decimals: 2), Decimal(string: "1.12"))
        XCTAssertEqual(parse("1.5", locale: enUS, decimals: 0), Decimal(1))
    }

    /// No `Double` anywhere on the path: a value past 15 significant digits
    /// keeps its low-order digits.
    func testLargeAmountsKeepEveryDigit() {
        XCTAssertEqual(
            parse("123456789012345.678901", locale: enUS, decimals: 6),
            Decimal(string: "123456789012345.678901")
        )
    }

    // MARK: - The spelling the app writes back

    /// The amount field's percentage presets emit grouped text, which is exactly
    /// the shape `parse` refuses. Anything the app re-renders must therefore come
    /// back in a spelling the parser always accepts.
    func testPlainSpellingCarriesNoGroupingSeparatorAndParsesBack() {
        let cases: [(Decimal, Locale, String)] = [
            (Decimal(1000), enUS, "1000"),
            (Decimal(1000), deDE, "1000"),
            (Decimal(12_345_678), enUS, "12345678"),
            (Decimal(string: "1234.5") ?? .zero, enUS, "1234.5"),
            (Decimal(string: "1234.5") ?? .zero, deDE, "1234,5")
        ]

        for (amount, locale, expected) in cases {
            let spelling = IBCTransferAmount.plainSpelling(of: amount, decimals: 6, locale: locale)
            XCTAssertEqual(spelling, expected)
            XCTAssertEqual(
                parse(spelling, locale: locale),
                amount,
                "\(spelling) must read back as the amount it was rendered from"
            )
        }
    }

    /// Truncated, never rounded up: a preset derived from the ceiling must not
    /// render as a value above it.
    func testPlainSpellingTruncatesRatherThanRoundingUp() {
        XCTAssertEqual(
            IBCTransferAmount.plainSpelling(of: Decimal(string: "1.9999999") ?? .zero, decimals: 6, locale: enUS),
            "1.999999"
        )
    }

    // MARK: - The validator

    private func validator(balance: Decimal, locale: Locale) -> IBCTransferAmountValidator {
        IBCTransferAmountValidator(balance: balance, decimals: 6, locale: locale)
    }

    func testValidatorRefusesTheAmbiguousAmountRatherThanAcceptingTenTimesIt() {
        // 15 would be over the balance anyway; the point is that it is rejected
        // as *invalid*, so the builder and the field agree on what the text says.
        XCTAssertThrowsError(try validator(balance: Decimal(100), locale: enUS).validate(value: "1,5"))
    }

    func testValidatorAcceptsWithinBalanceAndRejectsOver() {
        let subject = validator(balance: Decimal(string: "1.5") ?? .zero, locale: enUS)
        XCTAssertNoThrow(try subject.validate(value: "1.5"))
        XCTAssertNoThrow(try subject.validate(value: "0.000001"))
        XCTAssertThrowsError(try subject.validate(value: "1.500001"))
    }

    func testValidatorRejectsZeroAndEmpty() {
        let subject = validator(balance: Decimal(100), locale: enUS)
        XCTAssertThrowsError(try subject.validate(value: "0"))
        XCTAssertThrowsError(try subject.validate(value: .empty))
    }
}
