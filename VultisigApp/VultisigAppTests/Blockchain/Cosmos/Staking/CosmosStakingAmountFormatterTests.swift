//
//  CosmosStakingAmountFormatterTests.swift
//  VultisigAppTests
//
//  Pins the human-decimal → base-unit conversion shared across the four
//  cosmos staking builders. Rounding is `.down` so the user never
//  over-stakes by truncation; comma-as-decimal-separator locales are
//  normalized to a dot before parsing.
//

@testable import VultisigApp
import XCTest

final class CosmosStakingAmountFormatterTests: XCTestCase {

    func testWholeNumberRoundtrip() {
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: "1", decimals: 6),
            "1000000"
        )
    }

    func testFractionalAmountRoundsDown() {
        // 1.999999 LUNA → 1,999,999 uluna (truncate to integer base units).
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: "1.999999", decimals: 6),
            "1999999"
        )
    }

    func testAmountWithMoreFractionalDigitsThanChainSupportsTruncates() {
        // 1.9999999 (7 fractional digits) at 6-decimals → 1,999,999 uluna.
        // Rounding `.down` prevents accidentally over-staking by 1 uluna.
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: "1.9999999", decimals: 6),
            "1999999"
        )
    }

    func testCommaDecimalSeparatorIsNormalized() {
        // German / French locale input style.
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: "1,5", decimals: 6),
            "1500000"
        )
    }

    func testParseFailureReturnsZero() {
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: "abc", decimals: 6),
            "0"
        )
    }

    func testZeroAmountReturnsZero() {
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: "0", decimals: 6),
            "0"
        )
    }
}
