//
//  LiFiSlippageTests.swift
//  VultisigAppTests
//
//  Pins the bps → LI.FI decimal-fraction conversion. LI.FI's `slippage`
//  query param is a fraction in [0,1] (not a percent, not bps), so the user's
//  basis-point slippage must be divided by 10_000 and rendered with a dot
//  separator regardless of locale. `Auto` (nil) must omit the param entirely
//  so LI.FI applies its own default rather than receiving "0".
//

import XCTest
@testable import VultisigApp

final class LiFiSlippageTests: XCTestCase {

    func testCommonPresetsMapToDecimalFraction() {
        XCTAssertEqual(LiFiService.lifiSlippageFraction(bps: 50), "0.005")
        XCTAssertEqual(LiFiService.lifiSlippageFraction(bps: 100), "0.01")
        XCTAssertEqual(LiFiService.lifiSlippageFraction(bps: 300), "0.03")
    }

    func testAutoReturnsNilSoParamIsOmitted() {
        XCTAssertNil(LiFiService.lifiSlippageFraction(bps: nil))
    }

    func testValueIsClampedAtFiftyPercent() {
        // 10_000 bps (100%) clamps to the 5000 bps (50%) ceiling, matching the
        // 1inch path, so a bogus custom value can't produce a >1 fraction.
        XCTAssertEqual(LiFiService.lifiSlippageFraction(bps: 10_000), "0.5")
        XCTAssertEqual(LiFiService.lifiSlippageFraction(bps: 5000), "0.5")
        XCTAssertEqual(LiFiService.lifiSlippageFraction(bps: 5001), "0.5")
    }

    func testNegativeValueClampsToZero() {
        XCTAssertEqual(LiFiService.lifiSlippageFraction(bps: -100), "0")
    }

    func testFractionUsesDotDecimalSeparator() {
        // Locale-independent: the rendered fraction must contain a dot and
        // never a comma, even though some locales localize the separator.
        let fraction = LiFiService.lifiSlippageFraction(bps: 50)
        XCTAssertEqual(fraction, "0.005")
        XCTAssertTrue(fraction?.contains(".") ?? false)
        XCTAssertFalse(fraction?.contains(",") ?? true)
    }
}
