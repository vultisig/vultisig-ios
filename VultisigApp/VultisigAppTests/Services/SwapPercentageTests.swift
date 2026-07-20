//
//  SwapPercentageTests.swift
//  VultisigAppTests
//
//  Coverage for the "25 / 50 / 75 / 100%" swap presets. Exercises the
//  production helpers — `PercentageAmountLogic` and
//  `SwapCryptoLogic.percentageAmountText` — rather than re-deriving the math,
//  so a regression in the rule fails here.
//

import BigInt
import XCTest
@testable import VultisigApp

// The amount text carries the current locale's decimal separator, so hardcoded
// `.`-separated expectations fail on comma-decimal simulators (e.g. de_DE).
// `.localeDecimal` rewrites the expected value with the current separator.
private extension String {
    var localeDecimal: String {
        let separator = Locale.current.decimalSeparator ?? "."
        return replacingOccurrences(of: ".", with: separator)
    }
}

@MainActor
final class SwapPercentageTests: XCTestCase {

    // MARK: - Precision rule

    func testDecimalPlacesCapsAtEightAndNeverExceedsTheAsset() {
        XCTAssertEqual(PercentageAmountLogic.decimalPlaces(coinDecimals: 0), 0)
        XCTAssertEqual(PercentageAmountLogic.decimalPlaces(coinDecimals: 2), 2)
        XCTAssertEqual(PercentageAmountLogic.decimalPlaces(coinDecimals: 6), 6)
        XCTAssertEqual(PercentageAmountLogic.decimalPlaces(coinDecimals: 8), 8)
        XCTAssertEqual(PercentageAmountLogic.decimalPlaces(coinDecimals: 9), 8)
        XCTAssertEqual(PercentageAmountLogic.decimalPlaces(coinDecimals: 18), 8)
    }

    // MARK: - BTC: the reported bug

    /// 25% of 0.00021322 BTC is 0.000053305 — below the old hardcoded 4-decimal
    /// floor, so the button used to produce a zero-value swap.
    func testBtcSmallBalancePercentagesAreNonZero() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "21322")

        XCTAssertEqual(text(25, btc), "0.0000533".localeDecimal)
        XCTAssertEqual(text(50, btc), "0.00010661".localeDecimal)
        XCTAssertEqual(text(75, btc), "0.00015991".localeDecimal)
        XCTAssertEqual(text(100, btc), "0.00021322".localeDecimal)

        XCTAssertNotEqual(text(25, btc), "0", "25% must not truncate away to a zero-value swap")
    }

    func testBtcNativeHundredPercentReservesTheNetworkFee() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "21322")
        XCTAssertEqual(text(100, btc, fee: BigInt(1_000)), "0.00020322".localeDecimal)
    }

    func testNativeHundredPercentFloorsAtZeroWhenFeeExceedsBalance() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "21322")
        XCTAssertEqual(text(100, btc, fee: BigInt(50_000)), "0")
    }

    // MARK: - 100% strands nothing

    func testNonNativeHundredPercentReturnsTheExactFullBalance() {
        let wbtc = makeCoin(.ethereum, ticker: "WBTC", decimals: 8, isNative: false, rawBalance: "21322")
        XCTAssertEqual(text(100, wbtc, fee: BigInt(1_000)), "0.00021322".localeDecimal)
    }

    /// The old 4-decimal truncation stranded up to 9_999 base units of an
    /// 8-decimal token on every Max.
    func testNonNativeHundredPercentDoesNotStrandSubUnitDust() {
        let wbtc = makeCoin(.ethereum, ticker: "WBTC", decimals: 8, isNative: false, rawBalance: "123459999")
        XCTAssertEqual(text(100, wbtc), "1.23459999".localeDecimal)
    }

    // MARK: - Other precisions

    func testUsdcSixDecimals() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "1234567")

        XCTAssertEqual(text(25, usdc), "0.308641".localeDecimal)
        XCTAssertEqual(text(50, usdc), "0.617283".localeDecimal)
        XCTAssertEqual(text(100, usdc), "1.234567".localeDecimal)
    }

    /// 18-decimal assets: fractional presets stop at the 8-place cap, while
    /// 100% still hands back every last wei.
    func testEighteenDecimalTokenCapsFractionsAtEightPlacesButNotHundredPercent() {
        let dai = makeCoin(.ethereum, ticker: "DAI", decimals: 18, isNative: false, rawBalance: "1234567890123456789")

        XCTAssertEqual(text(25, dai), "0.30864197".localeDecimal)
        XCTAssertEqual(text(75, dai), "0.92592591".localeDecimal)
        XCTAssertEqual(text(100, dai), "1.234567890123456789".localeDecimal)
    }

    /// The case that rules out a `max(4, decimals)` floor: a 2-decimal asset
    /// cannot represent 4 places, so a preset must never claim them.
    func testSubFourDecimalAssetIsNotPaddedBeyondItsPrecision() {
        let coin = makeCoin(.ethereum, ticker: "LOWDP", decimals: 2, isNative: false, rawBalance: "12345")

        XCTAssertEqual(text(25, coin), "30.86".localeDecimal)
        XCTAssertEqual(text(50, coin), "61.72".localeDecimal)
        XCTAssertEqual(text(100, coin), "123.45".localeDecimal)
    }

    func testZeroDecimalAssetHasNoFractionalPart() {
        let coin = makeCoin(.ethereum, ticker: "ZERODP", decimals: 0, isNative: false, rawBalance: "12345")
        XCTAssertEqual(text(100, coin), "12345")
    }

    // MARK: - Unsupported input

    func testUnsupportedPercentageReturnsNil() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "21322")
        XCTAssertNil(SwapCryptoLogic.percentageAmountText(percentage: 33, fromCoin: btc, fee: 0))
        XCTAssertNil(SwapCryptoLogic.percentageAmountText(percentage: 0, fromCoin: btc, fee: 0))
    }

    func testZeroBalanceReturnsZero() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "0")
        XCTAssertEqual(text(50, btc), "0")
    }

    // MARK: - Raw conversion clamp

    /// `Coin.raw(for:)` rounds UP and the amount field round-trips through a
    /// Double-backed `NumberFormatter`, so a full-precision 18-decimal balance
    /// parses back slightly high. Unclamped that converts to more base units
    /// than the wallet holds and the swap fails on chain.
    func testHundredPercentOfEighteenDecimalBalanceConvertsToExactlyRawBalance() throws {
        let rawBalance = "1234567890123456789"
        let dai = makeCoin(.ethereum, ticker: "DAI", decimals: 18, isNative: false, rawBalance: rawBalance)
        let expected = BigInt(rawBalance) ?? .zero
        let amount = try XCTUnwrap(text(100, dai))

        XCTAssertGreaterThan(
            dai.raw(for: amount.toDecimal()),
            expected,
            "precondition: the unclamped conversion overshoots the balance"
        )
        XCTAssertEqual(
            SwapCryptoLogic.amountInCoinDecimal(fromAmount: amount, fromCoin: dai),
            expected
        )
    }

    func testHundredPercentOfEightDecimalBalanceConvertsToExactlyRawBalance() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "21322")
        XCTAssertEqual(
            SwapCryptoLogic.amountInCoinDecimal(fromAmount: text(100, btc) ?? "", fromCoin: btc),
            BigInt(21_322)
        )
    }

    /// The broadcast amount is capped at the balance in every case, not just
    /// for the presets — the chain rejects anything larger.
    func testAmountAboveBalanceNeverBroadcastsMoreThanTheBalance() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "21322")
        XCTAssertEqual(
            SwapCryptoLogic.amountInCoinDecimal(fromAmount: "0.001", fromCoin: btc),
            BigInt(21_322)
        )
    }

    /// Capping the broadcast amount must not hide an over-spend: the
    /// insufficient-funds check runs on a separate `Decimal` path and still
    /// rejects the same input.
    func testCappingDoesNotHideOverSpendFromTheBalanceCheck() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "21322")
        XCTAssertEqual(
            SwapCryptoLogic.balanceError(fromCoin: btc, feeCoin: btc, fromAmount: "0.001", fee: 0),
            .insufficientFunds
        )
    }

    /// A balance that hasn't loaded yet must not cap a legitimate amount to
    /// zero — this is also what `SwapCryptoLogicTests` pins for an unset
    /// balance.
    func testUnloadedBalanceDoesNotCapTheAmount() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "")
        XCTAssertEqual(
            SwapCryptoLogic.amountInCoinDecimal(fromAmount: "1.5", fromCoin: btc),
            BigInt(150_000_000)
        )
    }

    // MARK: - Helpers

    private func text(_ percentage: Int, _ coin: Coin, fee: BigInt = 0) -> String? {
        SwapCryptoLogic.percentageAmountText(percentage: percentage, fromCoin: coin, fee: fee)
    }

    private func makeCoin(
        _ chain: Chain,
        ticker: String,
        decimals: Int,
        isNative: Bool,
        rawBalance: String
    ) -> Coin {
        let coin = Coin(
            asset: CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative),
            address: "test-address-\(ticker)",
            hexPublicKey: ""
        )
        coin.rawBalance = rawBalance
        return coin
    }
}
