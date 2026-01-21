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
}
