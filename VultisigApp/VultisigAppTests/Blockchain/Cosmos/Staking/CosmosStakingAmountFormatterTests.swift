//
//  CosmosStakingAmountFormatterTests.swift
//  VultisigAppTests
//
//  Pins the Decimal → base-unit conversion shared across the three
//  cosmos staking builders. Rounding is `.down` so the user never
//  over-stakes by truncation. Input is the `Decimal` the form parsed.
//

@testable import VultisigApp
import XCTest

final class CosmosStakingAmountFormatterTests: XCTestCase {

    func testWholeNumberRoundtrip() {
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: 1, decimals: 6),
            "1000000"
        )
    }

    func testFractionalAmountRoundsDown() {
        // 1.999999 LUNA → 1,999,999 uluna (truncate to integer base units).
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: Decimal(string: "1.999999") ?? 0, decimals: 6),
            "1999999"
        )
    }

    func testAmountWithMoreFractionalDigitsThanChainSupportsTruncates() {
        // 1.9999999 (7 fractional digits) at 6-decimals → 1,999,999 uluna.
        // Rounding `.down` prevents accidentally over-staking by 1 uluna.
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: Decimal(string: "1.9999999") ?? 0, decimals: 6),
            "1999999"
        )
    }

    func testAmountAboveAThousandKeepsEveryDigit() {
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: Decimal(string: "1234.5") ?? 0, decimals: 6),
            "1234500000"
        )
    }

    func testZeroAmountReturnsZero() {
        XCTAssertEqual(
            CosmosStakingAmountFormatter.baseUnitsString(amount: 0, decimals: 6),
            "0"
        )
    }
}
