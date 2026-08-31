//
//  SwapRecommendedMinimumGuardTests.swift
//  VultisigAppTests
//
//  Pins the per-candidate minimum guard that keeps below-floor native routes
//  out of the ranked set and therefore out of the Select-route picker.
//

import XCTest
@testable import VultisigApp

final class SwapRecommendedMinimumGuardTests: XCTestCase {

    /// 0.00014844 BTC in THORChain 1e8 fixed point.
    private let normalizedBtcAmount = Decimal(14_844)

    /// Historical Mayanode floor at 30 affiliate bps for the reported swap.
    func testGuardRejectsAmountBelowNodeFloor() {
        let verdict = SwapService.belowRecommendedMinimumError(
            normalizedAmount: normalizedBtcAmount,
            recommendedMinAmountIn: "24092",
            fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
        )

        guard case .lessThenMinSwapAmount(let amount)? = verdict else {
            return XCTFail("A node floor above the swap amount must produce the minimum-amount verdict")
        }
        XCTAssertEqual(amount, "0.00024092 BTC")
    }

    /// Historical Mayanode floor at 50 affiliate bps for the same swap.
    func testGuardAllowsAmountAboveNodeFloor() {
        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedBtcAmount,
                recommendedMinAmountIn: "14455",
                fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
            )
        )
    }

    /// Historical Mayanode fallback floor when the request sent zero affiliate bps.
    func testGuardAllowsAmountWithoutAffiliateFloor() {
        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedBtcAmount,
                recommendedMinAmountIn: "8944",
                fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
            )
        )
    }

    func testGuardComparesNodeFixedPointUnits() {
        let bitcoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
        let oneBitcoin = Decimal(1)

        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: oneBitcoin * bitcoin.thorswapMultiplier,
                recommendedMinAmountIn: "24092",
                fromCoin: bitcoin
            )
        )
        XCTAssertNotNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: oneBitcoin,
                recommendedMinAmountIn: "24092",
                fromCoin: bitcoin
            ),
            "Skipping normalization must be observable"
        )
    }

    func testGuardUsesMayaNativeScaleForSourceCoin() {
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10)
        XCTAssertEqual(cacao.thorswapMultiplier, Decimal(10_000_000_000))

        let verdict = SwapService.belowRecommendedMinimumError(
            normalizedAmount: Decimal(10) * cacao.thorswapMultiplier,
            recommendedMinAmountIn: "246000000000",
            fromCoin: cacao
        )

        guard case .lessThenMinSwapAmount(let amount)? = verdict else {
            return XCTFail("A Maya-native input below the floor must be rejected")
        }
        XCTAssertEqual(amount, "24.6 CACAO")
    }

    func testGuardUsesThorchainScaleForEighteenDecimalCoin() {
        let ethereum = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        XCTAssertEqual(ethereum.thorswapMultiplier, Decimal(100_000_000))

        let verdict = SwapService.belowRecommendedMinimumError(
            normalizedAmount: Decimal(string: "0.001")! * ethereum.thorswapMultiplier,
            recommendedMinAmountIn: "1000000",
            fromCoin: ethereum
        )

        guard case .lessThenMinSwapAmount(let amount)? = verdict else {
            return XCTFail("0.001 ETH is below a 0.01 ETH floor")
        }
        XCTAssertEqual(amount, "0.01 ETH")
    }

    func testGuardAllowsAmountExactlyAtFloor() {
        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedBtcAmount,
                recommendedMinAmountIn: "14844",
                fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
            )
        )
    }

    func testGuardFailsOpenOnMalformedFloor() {
        let bitcoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8)

        for floor in ["", "n/a", "null"] {
            XCTAssertNil(
                SwapService.belowRecommendedMinimumError(
                    normalizedAmount: normalizedBtcAmount,
                    recommendedMinAmountIn: floor,
                    fromCoin: bitcoin
                ),
                "A malformed floor (\(floor)) must not block the quote"
            )
        }
    }

    func testGuardAllowsZeroFloor() {
        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedBtcAmount,
                recommendedMinAmountIn: "0",
                fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
            )
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int) -> Coin {
        let asset = CoinMeta.make(
            chain: chain,
            ticker: ticker,
            decimals: decimals,
            isNativeToken: true
        )
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }
}
