//
//  LiFiSlippageTests.swift
//  VultisigAppTests
//
//  Pins the bps → LI.FI decimal-fraction conversion. LI.FI's `slippage`
//  query param is a fraction in [0,1] (not a percent, not bps), so the user's
//  basis-point slippage must be divided by 10_000 and rendered with a dot
//  separator regardless of locale. `Auto` (nil) must resolve to the same
//  stable/volatile pair tiers as the SDK rather than omitting the parameter.
//

import XCTest
@testable import VultisigApp

final class LiFiSlippageTests: XCTestCase {

    func testCommonPresetsMapToDecimalFraction() {
        XCTAssertEqual(fraction(bps: 50), "0.005")
        XCTAssertEqual(fraction(bps: 100), "0.01")
        XCTAssertEqual(fraction(bps: 300), "0.03")
    }

    func testAutoUsesThirtyBasisPointsForStablePair() {
        XCTAssertEqual(fraction(bps: nil, from: "USDC", to: "USDT"), "0.003")
        XCTAssertEqual(fraction(bps: nil, from: "dai", to: "usdc"), "0.003")
    }

    func testAutoUsesOneHundredBasisPointsForVolatilePair() {
        XCTAssertEqual(fraction(bps: nil, from: "ETH", to: "USDC"), "0.01")
        XCTAssertEqual(fraction(bps: nil, from: "SOL", to: "BONK"), "0.01")
    }

    func testStableTickerSetPinsCanonicalList() {
        // Mirrors STABLE_TICKERS in vultisig-sdk's getLifiSwapQuote.ts.
        XCTAssertEqual(
            LiFiService.stableTickers,
            ["USDC", "USDT", "DAI", "BUSD", "TUSD", "FRAX", "USDP", "GUSD", "LUSD", "USDD", "FDUSD", "PYUSD"]
        )
    }

    func testExplicitSlippageOverridesAutoTier() {
        XCTAssertEqual(fraction(bps: 50, from: "ETH", to: "USDC"), "0.005")
        XCTAssertEqual(fraction(bps: 300, from: "USDC", to: "USDT"), "0.03")
    }

    func testQuoteRequestAlwaysEncodesAutoSlippage() {
        let slippage = fraction(bps: nil, from: "USDC", to: "USDT")
        let request = LiFiAPI.quote(params: .init(
            fromChain: "1",
            toChain: "10",
            fromToken: "USDC",
            toToken: "USDT",
            fromAmount: "1000000",
            fromAddress: "0x1111111111111111111111111111111111111111",
            toAddress: "0x2222222222222222222222222222222222222222",
            integrator: nil,
            fee: nil,
            slippage: slippage
        ))

        guard case let .requestParameters(params, _) = request.task else {
            return XCTFail("LI.FI quote must build requestParameters")
        }
        XCTAssertEqual(params["slippage"] as? String, "0.003")
    }

    func testValueIsClampedAtFiftyPercent() {
        // 10_000 bps (100%) clamps to the 5000 bps (50%) ceiling, matching the
        // 1inch path, so a bogus custom value can't produce a >1 fraction.
        XCTAssertEqual(fraction(bps: 10_000), "0.5")
        XCTAssertEqual(fraction(bps: 5000), "0.5")
        XCTAssertEqual(fraction(bps: 5001), "0.5")
    }

    func testNegativeValueClampsToZero() {
        XCTAssertEqual(fraction(bps: -100), "0")
    }

    func testFractionUsesDotDecimalSeparator() {
        // Locale-independent: the rendered fraction must contain a dot and
        // never a comma, even though some locales localize the separator.
        let fraction = fraction(bps: 50)
        XCTAssertEqual(fraction, "0.005")
        XCTAssertTrue(fraction.contains("."))
        XCTAssertFalse(fraction.contains(","))
    }

    private func fraction(
        bps: Int?,
        from: String = "ETH",
        to: String = "USDC"
    ) -> String {
        LiFiService.lifiSlippageFraction(bps: bps, fromTicker: from, toTicker: to)
    }
}
