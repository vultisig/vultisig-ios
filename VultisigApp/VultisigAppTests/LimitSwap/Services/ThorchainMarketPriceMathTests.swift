//
//  ThorchainMarketPriceMathTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

/// `ThorchainService.marketPrice` — the 1e8 fixed-point math behind the
/// limit-swap market-price reference, plus its three throw paths. Previously
/// only the mock was exercised; this pins the real derivation.
final class ThorchainMarketPriceMathTests: XCTestCase {

    func testOneBtcToSixteenAndAHalfEth() throws {
        // 16.5 ETH out (1e8 units) for 1 BTC (8 dp) in → 16.5 target per source.
        let price = try ThorchainService.marketPrice(
            expectedAmountOut: "1650000000",  // 16.5 × 1e8
            sourceAmount: BigInt(100_000_000), // 1 BTC
            sourceDecimals: 8
        )
        XCTAssertEqual(price, Decimal(string: "16.5")!)
    }

    func testOneEthToFractionalBtc() throws {
        // 0.0625 BTC out for 1 ETH (18 dp) in.
        let price = try ThorchainService.marketPrice(
            expectedAmountOut: "6250000",  // 0.0625 × 1e8
            sourceAmount: BigInt("1000000000000000000"), // 1 ETH
            sourceDecimals: 18
        )
        XCTAssertEqual(price, Decimal(string: "0.0625")!)
    }

    func testScalesByOneEightNotSourceDecimals() throws {
        // Half a BTC in → the price is still per-1-source-unit (target/source).
        let price = try ThorchainService.marketPrice(
            expectedAmountOut: "825000000",  // 8.25 ETH for 0.5 BTC
            sourceAmount: BigInt(50_000_000),
            sourceDecimals: 8
        )
        XCTAssertEqual(price, Decimal(string: "16.5")!) // 8.25 / 0.5
    }

    func testThrowsInvalidExpectedAmount() {
        XCTAssertThrowsError(
            try ThorchainService.marketPrice(expectedAmountOut: "not-a-number", sourceAmount: BigInt(1), sourceDecimals: 8)
        ) { error in
            guard case LimitSwapQuoteError.invalidExpectedAmount(let raw) = error else {
                return XCTFail("Expected invalidExpectedAmount, got \(error)")
            }
            XCTAssertEqual(raw, "not-a-number")
        }
    }

    func testThrowsZeroSourceAmount() {
        XCTAssertThrowsError(
            try ThorchainService.marketPrice(expectedAmountOut: "1650000000", sourceAmount: 0, sourceDecimals: 8)
        ) { error in
            XCTAssertEqual(error as? LimitSwapQuoteError, .zeroSourceAmount)
        }
    }

    // MARK: - thorchainQuoteAmount (native → 1e8 normalization for the quote)

    func testThorchainQuoteAmountLeaves8DecimalSourceUnchanged() {
        // RUNE/BTC: native smallest unit == 1e8, so 1 whole coin stays 1e8.
        let amount = ThorchainService.thorchainQuoteAmount(sourceAmount: BigInt(100_000_000), sourceDecimals: 8)
        XCTAssertEqual(amount, BigInt(100_000_000))
    }

    func testThorchainQuoteAmountScalesOneWholeCoinTo1e8ForAnyDecimals() {
        // 1 whole coin must always map to 1e8 THORChain units, regardless of the
        // coin's native decimals — this is the fix: 18-dec ETH no longer sends
        // 1e10× too much.
        let e8 = BigInt(10).power(8)
        XCTAssertEqual(ThorchainService.thorchainQuoteAmount(sourceAmount: BigInt(10).power(18), sourceDecimals: 18), e8)
        XCTAssertEqual(ThorchainService.thorchainQuoteAmount(sourceAmount: BigInt(10).power(6), sourceDecimals: 6), e8)
        XCTAssertEqual(ThorchainService.thorchainQuoteAmount(sourceAmount: BigInt(10).power(8), sourceDecimals: 8), e8)
    }

    func testThorchainQuoteAmountFractionalCoinPreservesPrecision() {
        // 0.5 ETH (18 dp) → 0.5e8 THORChain units. Multiply-first avoids
        // truncating to zero before the divide.
        let amount = ThorchainService.thorchainQuoteAmount(
            sourceAmount: BigInt("500000000000000000"), // 0.5 ETH
            sourceDecimals: 18
        )
        XCTAssertEqual(amount, BigInt(50_000_000)) // 0.5 × 1e8
    }

    func testMarketPriceIsScaleInvariantAcrossSourceDecimals() throws {
        // The bug: an 18-decimal source (ETH) produced a market price ~1e10× too
        // big because the native amount was sent to THORChain unscaled. With
        // `thorchainQuoteAmount` normalization, an 18-decimal source and an
        // 8-decimal source at the SAME underlying rate yield the SAME price.
        //
        // Model THORChain as a scale-preserving oracle: for a 1e8-unit input `T`
        // at rate `r` (target-natural per source-natural) it returns `T × r`
        // (also in 1e8 units).
        let rate = Decimal(string: "2870")! // e.g. USDC per ETH

        func priceForSource(nativeWholeCoin: BigInt, decimals: Int) throws -> Decimal {
            let thorAmount = ThorchainService.thorchainQuoteAmount(sourceAmount: nativeWholeCoin, sourceDecimals: decimals)
            let expected = Decimal(string: thorAmount.description)! * rate // 1e8-unit expected_amount_out
            let expectedString = NSDecimalNumber(decimal: expected).stringValue
            return try ThorchainService.marketPrice(
                expectedAmountOut: expectedString,
                sourceAmount: nativeWholeCoin,
                sourceDecimals: decimals
            )
        }

        let price8 = try priceForSource(nativeWholeCoin: BigInt(10).power(8), decimals: 8)
        let price18 = try priceForSource(nativeWholeCoin: BigInt(10).power(18), decimals: 18)

        XCTAssertEqual(price8, rate)
        XCTAssertEqual(price18, rate)
        XCTAssertEqual(price8, price18, "Same rate must yield the same price regardless of source decimals")
    }
}
