//
//  DecimalExtensionTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class DecimalExtensionTests: XCTestCase {

    private let separator = Locale.current.decimalSeparator ?? "."

    /// Builds an expected string using the host locale's decimal separator so the
    /// assertions hold regardless of where the suite runs.
    private func expected(_ value: String) -> String {
        value.replacingOccurrences(of: ".", with: separator)
    }

    private func price(_ value: String) -> String {
        Decimal(string: value)!.formatToFiatPrice(includeCurrencySymbol: false)
    }

    // MARK: - Compact subscript notation (issue #4706 / SDK #918 parity)

    func testFormatToFiatPriceUsesSubscriptForSevenLeadingZeros() {
        XCTAssertEqual(price("0.00000003"), expected("0.0₇3"))
    }

    func testFormatToFiatPriceUsesSubscriptForFourLeadingZeros() {
        XCTAssertEqual(price("0.00001234"), expected("0.0₄1234"))
    }

    func testFormatToFiatPriceStaysPlainForThreeLeadingZeros() {
        // Fewer than four leading zeros keeps plain decimals (no subscript).
        XCTAssertEqual(price("0.0001234"), expected("0.0001234"))
    }

    func testFormatToFiatPriceBoundaryThreeZerosPlainFourZerosSubscript() {
        XCTAssertEqual(price("0.0001"), expected("0.0001"))    // 3 zeros -> plain
        XCTAssertEqual(price("0.00001"), expected("0.0₄1"))    // 4 zeros -> subscript
    }

    func testFormatToFiatPriceSubscriptAtExactlyFourLeadingZeros() {
        // 0.00006 has four leading zeros, so it collapses to a subscript count, matching the shared
        // SDK/desktop contract (threshold = 4). The issue table labelled this row "<4 zeros", but
        // that is an off-by-one miscount: the "6" sits in the fifth decimal place.
        XCTAssertEqual(price("0.00006"), expected("0.0₄6"))
    }

    func testFormatToFiatPriceKeepsUpToFourSignificantFigures() {
        XCTAssertEqual(price("0.00456"), expected("0.00456"))   // 2 zeros, 3 sig figs
        XCTAssertEqual(price("0.0054"), expected("0.0054"))     // USTC-like, 2 sig figs
    }

    func testFormatToFiatPriceTrimsTrailingZerosInSubscript() {
        // 0.000012 keeps only the significant "12", not "1200".
        XCTAssertEqual(price("0.000012"), expected("0.0₄12"))
    }

    func testFormatToFiatPriceRoundsHalfUpToFourSignificantFigures() {
        // A fifth significant figure rounds the fourth up (half away from zero).
        XCTAssertEqual(price("0.000012345"), expected("0.0₄1235"))
    }

    func testFormatToFiatPriceRoundingCarryShrinksZeroRunOutOfSubscript() {
        // 0.000099999 rounds up to 0.0001, dropping from four leading zeros to three (plain).
        XCTAssertEqual(price("0.000099999"), expected("0.0001"))
    }

    func testFormatToFiatPriceVeryTinyValueUsesSubscriptCount() {
        XCTAssertEqual(price("0.000000000001"), expected("0.0₁₁1"))
    }

    func testFormatToFiatPriceCurrencyPathProducesSubscript() {
        // The currency-symbol path (default) still emits the subscript notation, whatever the host
        // locale/currency symbol is.
        let formatted = Decimal(string: "0.00000003")!.formatToFiatPrice()
        XCTAssertTrue(formatted.contains("₇"), formatted)
        XCTAssertTrue(formatted.contains(expected("0.0")), formatted)
    }

    func testFormatToFiatPriceSubscriptStableUnderNonLatinDigitShaping() {
        // The sub-cent branch builds an internal canonical "0.xxx" string and inspects it with
        // hasPrefix("0."). That only holds if the internal NumberFormatter emits ASCII digits, so
        // `formatToFiatPrice` pins it to en_US_POSIX — otherwise an ambient non-Latin-digit locale
        // (e.g. Arabic-Indic numerals) would shape the digits and send tiny prices down the
        // non-subscript fallback. A unit test can't reassign the process-wide `Locale.current`, so
        // we validate the mechanism the fix relies on and pin the expectation.
        func canonicalString(locale: Locale) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = locale
            formatter.usesGroupingSeparator = false
            formatter.decimalSeparator = "."
            formatter.maximumFractionDigits = 11
            formatter.minimumFractionDigits = 0
            return formatter.string(from: NSDecimalNumber(decimal: Decimal(string: "0.00000003")!)) ?? ""
        }

        // The pinned (fixed) formatter always yields an ASCII, "0."-prefixed string, so the
        // hasPrefix("0.") guard passes and the subscript path is taken.
        XCTAssertTrue(canonicalString(locale: Locale(identifier: "en_US_POSIX")).hasPrefix("0."))

        // The subscript output is still produced for a tiny price regardless of the host locale.
        XCTAssertEqual(price("0.00000003"), expected("0.0₇3"))

        // Demonstrate the failure mode the pin defends against: an Arabic-Indic-digit locale shapes
        // the digits away from ASCII, so the raw string does not start with "0.". Only asserted when
        // the runtime ICU data actually shapes the digits, keeping the test deterministic.
        let arabic = canonicalString(locale: Locale(identifier: "ar_EG"))
        if let first = arabic.first, !first.isASCII {
            XCTAssertFalse(
                arabic.hasPrefix("0."),
                "Non-Latin digit shaping should not start with ASCII '0.' — the case the en_US_POSIX pin fixes."
            )
        }
    }

    // MARK: - Standard formatting is unchanged

    func test_formatToFiatPrice_fallsBackToStandardAtExactlyOneCent() {
        let value = Decimal(string: "0.01")!
        XCTAssertEqual(value.formatToFiatPrice(includeCurrencySymbol: false), value.formatToFiat(includeCurrencySymbol: false))
        XCTAssertEqual(value.formatToFiatPrice(includeCurrencySymbol: false), expected("0.01"))
    }

    func test_formatToFiatPrice_fallsBackToStandardAboveOneCent() {
        let value = Decimal(string: "1.50")!
        XCTAssertEqual(value.formatToFiatPrice(includeCurrencySymbol: false), value.formatToFiat(includeCurrencySymbol: false))
        XCTAssertEqual(value.formatToFiatPrice(includeCurrencySymbol: false), expected("1.50"))
    }

    func test_formatToFiatPrice_fallsBackToStandardForZero() {
        let value = Decimal(0)
        XCTAssertEqual(value.formatToFiatPrice(includeCurrencySymbol: false), value.formatToFiat(includeCurrencySymbol: false))
        XCTAssertEqual(value.formatToFiatPrice(includeCurrencySymbol: false), expected("0.00"))
    }
}
