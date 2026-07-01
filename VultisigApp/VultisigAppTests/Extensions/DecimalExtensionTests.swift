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

    func test_formatToFiatPrice_revealsSubCentPriceInsteadOfZero() {
        // LUNC-like price: standard 2dp formatting would show 0.00.
        XCTAssertEqual(price("0.00006"), expected("0.00006"))
    }

    func test_formatToFiatPrice_revealsTwoSignificantFiguresOfLongSubCentPrice() {
        XCTAssertEqual(price("0.00006123"), expected("0.000061"))
    }

    func test_formatToFiatPrice_showsTwoSignificantFiguresForMidSubCentPrice() {
        // USTC-like price.
        XCTAssertEqual(price("0.0054"), expected("0.0054"))
    }

    func test_formatToFiatPrice_capsPrecisionAtEightFractionDigits() {
        // Two significant figures would need 9 digits; capped to 8 -> 0.00000012.
        XCTAssertEqual(price("0.000000123"), expected("0.00000012"))
    }

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
