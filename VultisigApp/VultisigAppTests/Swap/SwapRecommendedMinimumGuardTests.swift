//
//  SwapRecommendedMinimumGuardTests.swift
//  VultisigAppTests
//
//  Pins the per-candidate "below the node's recommended minimum" guard that
//  keeps a THORChain/MAYAChain route out of the ranked candidate set (and
//  therefore out of the Select-route picker).
//
//  The guard is the only thing standing between a below-floor native route and
//  a user manually selecting it, and every assertion here encodes a contract
//  that a refactor could break without any visible symptom:
//
//   * the comparison happens in the node's fixed-point scale, not human scale;
//   * the scale comes from the FROM-coin, so it is 1e10 for a Maya-native input
//     and 1e8 for everything else;
//   * a present-but-unparseable minimum fails OPEN (the quote is allowed through);
//   * when every provider fails, the minimum-amount verdict outranks a SwapKit
//     failure and relayed upstream text, so it is not demoted behind either.
//
//  The numeric fixtures are real Mayanode/THORNode responses captured for
//  BTC.BTC → ETH.ETH at 14844 sat, which is why the same amount both clears and
//  fails the floor depending only on the affiliate bps the app sent.
//

import XCTest
@testable import VultisigApp

final class SwapRecommendedMinimumGuardTests: XCTestCase {

    /// 0.00014844 BTC in THORChain 1e8 fixed point.
    private let normalizedBtcAmount = Decimal(14844)

    // MARK: - Live-captured Mayanode floors

    /// Mayanode returned this floor when the request carried `affiliate_bps=30`
    /// (a vault on the 20 bps VULT tier). Above the amount, so Maya is dropped.
    func testBelowRecommendedMinimumFiresWhenNodeFloorExceedsAmount() {
        let verdict = SwapService.belowRecommendedMinimumError(
            normalizedAmount: normalizedBtcAmount,
            recommendedMinAmountIn: "24092",
            fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
        )

        guard case .lessThenMinSwapAmount(let amount)? = verdict else {
            return XCTFail("A node floor above the swap amount must produce the minimum-amount verdict")
        }
        XCTAssertEqual(
            amount,
            "0.00024092 BTC",
            "The recommended amount must be scaled back out of node fixed point for display"
        )
    }

    /// Same swap, same node, `affiliate_bps=50` (the un-discounted Release rate):
    /// Mayanode's floor drops BELOW the amount, so the guard legitimately passes
    /// and the route stays in the candidate set. This is the behaviour that makes
    /// a below-economic-sense Maya route selectable, and it is a property of the
    /// node's answer rather than of this comparison.
    func testBelowRecommendedMinimumClearsWhenNodeFloorDropsBelowAmount() {
        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedBtcAmount,
                recommendedMinAmountIn: "14455",
                fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
            ),
            "A node floor below the swap amount must not drop the candidate"
        )
    }

    /// `affiliate_bps=0` (DEBUG builds send no affiliate fee) — floor lower again.
    func testBelowRecommendedMinimumClearsWithoutAffiliateFee() {
        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedBtcAmount,
                recommendedMinAmountIn: "8944",
                fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
            )
        )
    }

    // MARK: - Scale contract

    /// The guard must compare node fixed point against node fixed point. Feeding
    /// it the human-scale amount instead flips the verdict on a swap that is
    /// three orders of magnitude ABOVE the floor, which is exactly the kind of
    /// mistake that would silently delete THORChain/Maya from every picker.
    func testBelowRecommendedMinimumComparesInNodeScaleNotHumanScale() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
        let oneBitcoin = Decimal(1)

        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: oneBitcoin * btc.thorswapMultiplier,
                recommendedMinAmountIn: "24092",
                fromCoin: btc
            ),
            "1 BTC is far above the floor once normalized into node scale"
        )
        XCTAssertNotNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: oneBitcoin,
                recommendedMinAmountIn: "24092",
                fromCoin: btc
            ),
            "Skipping the multiplier must be observable — it wrongly rejects 1 BTC"
        )
    }

    /// THORChain quotes every off-chain asset in 1e8 regardless of the asset's
    /// own decimals, but a MAYAChain-native input is quoted at 1e10.
    /// `thorswapMultiplier` switches on the coin's chain, and the displayed
    /// recommended amount has to come back down by that same multiplier.
    func testBelowRecommendedMinimumUsesMayaNativeScaleForMayaSourceCoin() {
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10)
        XCTAssertEqual(cacao.thorswapMultiplier, Decimal(10_000_000_000))

        let verdict = SwapService.belowRecommendedMinimumError(
            normalizedAmount: Decimal(10) * cacao.thorswapMultiplier,
            recommendedMinAmountIn: "246000000000",
            fromCoin: cacao
        )

        guard case .lessThenMinSwapAmount(let amount)? = verdict else {
            return XCTFail("A Maya-native input below the floor must still be dropped")
        }
        XCTAssertEqual(amount, "24.6 CACAO", "Maya-native amounts scale by 1e10, not 1e8")
    }

    /// An 18-decimal EVM input is still quoted in THORChain's 1e8, so the
    /// multiplier must NOT follow the coin's own decimals here.
    func testBelowRecommendedMinimumUsesThorchainScaleForEighteenDecimalCoin() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        XCTAssertEqual(eth.thorswapMultiplier, Decimal(100_000_000))

        let verdict = SwapService.belowRecommendedMinimumError(
            normalizedAmount: Decimal(string: "0.001")! * eth.thorswapMultiplier,
            recommendedMinAmountIn: "1000000",
            fromCoin: eth
        )

        guard case .lessThenMinSwapAmount(let amount)? = verdict else {
            return XCTFail("0.001 ETH is below a 0.01 ETH floor")
        }
        XCTAssertEqual(amount, "0.01 ETH")
    }

    // MARK: - Boundary and fail-open behaviour

    /// The floor is *recommended*, so an amount exactly at it is allowed.
    func testBelowRecommendedMinimumAllowsAmountExactlyAtTheFloor() {
        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedBtcAmount,
                recommendedMinAmountIn: "14844",
                fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
            ),
            "An amount equal to the floor clears it — the comparison is strict"
        )
    }

    /// A malformed floor must not be able to block a swap. An *omitted* field
    /// never reaches here — `recommendedMinAmountIn` is required by
    /// `ThorchainSwapQuote`, so its absence fails decoding and drops the provider.
    func testBelowRecommendedMinimumFailsOpenOnUnparseableFloor() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
        for floor in ["", "n/a", "null"] {
            XCTAssertNil(
                SwapService.belowRecommendedMinimumError(
                    normalizedAmount: normalizedBtcAmount,
                    recommendedMinAmountIn: floor,
                    fromCoin: btc
                ),
                "An unparseable floor (\(floor)) must fail open"
            )
        }
    }

    /// A zero floor is the shape every node uses for "no minimum".
    func testBelowRecommendedMinimumClearsOnZeroFloor() {
        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedBtcAmount,
                recommendedMinAmountIn: "0",
                fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
            )
        )
    }

    // MARK: - Surfacing when every candidate failed

    /// The guard drops one candidate; the other providers still rank. Only when
    /// EVERY provider failed does an error reach the user, and the minimum-amount
    /// verdict must not lose that selection to a SwapKit failure or to relayed
    /// upstream text — it is the one failure that tells the user what to change.
    /// (Among other *classified* core-provider errors the order is still
    /// task-completion order; this pins only the two demotions that exist.)
    func testMinimumAmountErrorIsSurfacedAheadOfSwapKitAndUnclassifiedFailures() {
        let minimumError = SwapError.lessThenMinSwapAmount(amount: "0.00024092 BTC")

        let overSwapKit = SwapService.surfacedQuoteError(
            from: [SwapKitError.providerNotEnabled, minimumError]
        )
        XCTAssertEqual(
            overSwapKit as? SwapError,
            minimumError,
            "A core-provider minimum verdict must outrank a SwapKit failure"
        )

        let overRelayedText = SwapService.surfacedQuoteError(
            from: [SwapError.serverError(message: "raw node text"), minimumError]
        )
        XCTAssertEqual(
            overRelayedText as? SwapError,
            minimumError,
            "A typed minimum verdict must outrank relayed upstream text"
        )
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: true)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }
}
