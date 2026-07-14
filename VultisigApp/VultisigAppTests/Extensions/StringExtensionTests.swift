//
//  StringExtensionTests.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 25/04/25.
//

@testable import VultisigApp
import WalletCore
import XCTest
import BigInt

final class StringExtensionsTests: XCTestCase {

    func testParseDecimal_EN_US() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual("1.8".parseInput(locale: locale), Decimal(string: "1.8"))
        XCTAssertEqual("100,000.12".parseInput(locale: locale), Decimal(string: "100000.12"))
        XCTAssertEqual("12,345.67".parseInput(locale: locale), Decimal(string: "12345.67"))
        XCTAssertEqual("1,000,000.00".parseInput(locale: locale), Decimal(string: "1000000.00"))
        XCTAssertEqual("0".parseInput(locale: locale), Decimal.zero)
        XCTAssertEqual("0.0".parseInput(locale: locale), Decimal.zero)
        XCTAssertEqual("-123,456.78".parseInput(locale: locale), Decimal(string: "-123456.78"))
        XCTAssertEqual("0.000001".parseInput(locale: locale), Decimal(string: "0.000001"))
        XCTAssertEqual("1,000.000001".parseInput(locale: locale), Decimal(string: "1000.000001"))
    }

    func testParseDecimal_PT_BR() {
        let locale = Locale(identifier: "pt_BR")

        XCTAssertEqual("1,8".parseInput(locale: locale), Decimal(string: "1.8"))
        XCTAssertEqual("100.000,12".parseInput(locale: locale), Decimal(string: "100000.12"))
        XCTAssertEqual("12.345,67".parseInput(locale: locale), Decimal(string: "12345.67"))
        XCTAssertEqual("1.000.000,00".parseInput(locale: locale), Decimal(string: "1000000.00"))
        XCTAssertEqual("0".parseInput(locale: locale), Decimal.zero)
        XCTAssertEqual("0,0".parseInput(locale: locale), Decimal.zero)
        XCTAssertEqual("-123.456,78".parseInput(locale: locale), Decimal(string: "-123456.78"))
        XCTAssertEqual("0,000001".parseInput(locale: locale), Decimal(string: "0.000001"))
        XCTAssertEqual("1.000,000001".parseInput(locale: locale), Decimal(string: "1000.000001"))
    }

    func testParseDecimalWithExtraSpaces() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual("   1,234.56   ".parseInput(locale: locale), Decimal(string: "1234.56"))
    }

    func testParseInvalidInputs() {
        let locale = Locale(identifier: "en_US")

        XCTAssertNil("abc".parseInput(locale: locale))
        XCTAssertNil("1.8.3".parseInput(locale: locale))
        XCTAssertNil("1,000,000.00.50".parseInput(locale: locale))
        XCTAssertNil("1,,000.00".parseInput(locale: locale))
        XCTAssertNil("1.000..00".parseInput(locale: locale))
        XCTAssertNil("..1,000.00".parseInput(locale: locale))
        XCTAssertNil("\n\t1,234.56\t\n".parseInput(locale: locale))
    }

    func testEmptyInputs() {
        let locale = Locale(identifier: "en_US")

        XCTAssertNil("".parseInput(locale: locale))
        XCTAssertNil("     ".parseInput(locale: locale))
    }

    func testLargeNumbers() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual("9,999,999,999.99".parseInput(locale: locale), Decimal(string: "9999999999.99"))
        XCTAssertEqual("0.000000000001".parseInput(locale: locale), Decimal(string: "0.000000000001"))
    }

    func testDecimalFractions_EN_US() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual("0.9".parseInput(locale: locale), Decimal(string: "0.9"))
        XCTAssertEqual("0.9876823764827364".parseInput(locale: locale), Decimal(string: "0.9876823764827364"))
        XCTAssertEqual("0.00000001".parseInput(locale: locale), Decimal(string: "0.00000001"))
        XCTAssertEqual("0000.00000001".parseInput(locale: locale), Decimal(string: "0.00000001")) // leading zeros
    }

    func testDecimalFractions_PT_BR() {
        let locale = Locale(identifier: "pt_BR")

        XCTAssertEqual("0,9".parseInput(locale: locale), Decimal(string: "0.9"))
        XCTAssertEqual("0,9876823764827364".parseInput(locale: locale), Decimal(string: "0.9876823764827364"))
        XCTAssertEqual("0,00000001".parseInput(locale: locale), Decimal(string: "0.00000001"))
        XCTAssertEqual("0000,00000001".parseInput(locale: locale), Decimal(string: "0.00000001")) // leading zeros
    }

    func assertEuropeNumberParsing(for locale: Locale) {
        XCTAssertEqual("1,8".parseInput(locale: locale), Decimal(string: "1.8"))
        XCTAssertEqual("100.000,12".parseInput(locale: locale), Decimal(string: "100000.12"))
        XCTAssertEqual("12.345,67".parseInput(locale: locale), Decimal(string: "12345.67"))
        XCTAssertEqual("1.000.000,00".parseInput(locale: locale), Decimal(string: "1000000.00"))
        XCTAssertEqual("0".parseInput(locale: locale), Decimal.zero)
        XCTAssertEqual("0,0".parseInput(locale: locale), Decimal.zero)
        XCTAssertEqual("-123.456,78".parseInput(locale: locale), Decimal(string: "-123456.78"))
        XCTAssertEqual("0,00000001".parseInput(locale: locale), Decimal(string: "0.00000001"))
        XCTAssertEqual("1.000,000001".parseInput(locale: locale), Decimal(string: "1000.000001"))
    }

    func testParseDecimal_DE_DE() {
        assertEuropeNumberParsing(for: Locale(identifier: "de_DE"))
    }

// France use spaces as separators
//    func testParseDecimal_FR_FR() {
//        assertEuropeNumberParsing(for: Locale(identifier: "fr_FR"))
//    }

    func testParseDecimal_ES_ES() {
        assertEuropeNumberParsing(for: Locale(identifier: "es_ES"))
    }

    // MARK: - isDecimalInput

    func testIsDecimalInput_EN_US() {
        let locale = Locale(identifier: "en_US")

        XCTAssertTrue("12.5".isDecimalInput(locale: locale))
        XCTAssertTrue("12".isDecimalInput(locale: locale))
        XCTAssertTrue("".isDecimalInput(locale: locale))            // empty clears the field
        XCTAssertTrue("1,234.56".isDecimalInput(locale: locale))    // grouped paste is allowed
        XCTAssertTrue("1.".isDecimalInput(locale: locale))          // in-progress typing

        // Reject anything with a letter/symbol so it is NEVER silently reduced to
        // its digits (the corruption a strip-based filter would introduce).
        XCTAssertFalse("abc".isDecimalInput(locale: locale))
        XCTAssertFalse("12abc34".isDecimalInput(locale: locale))
        XCTAssertFalse("1e5".isDecimalInput(locale: locale))        // scientific notation
        XCTAssertFalse("$1.00".isDecimalInput(locale: locale))
        XCTAssertFalse("-5".isDecimalInput(locale: locale))         // sign
    }

    func testIsDecimalInput_PT_BR() {
        let locale = Locale(identifier: "pt_BR")

        XCTAssertTrue("12,5".isDecimalInput(locale: locale))        // comma is the decimal separator
        // Grouped paste ("." grouping, "," decimal) is valid AND parses correctly —
        // guards against the earlier separator-collapse corruption.
        XCTAssertTrue("1.234,56".isDecimalInput(locale: locale))
        XCTAssertEqual("1.234,56".parseInput(locale: locale), Decimal(string: "1234.56"))
        XCTAssertFalse("abc12,5".isDecimalInput(locale: locale))
    }
}
