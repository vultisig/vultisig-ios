//
//  LimitMathTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

final class LimitMathTests: XCTestCase {

    // MARK: - computeLim — integer prices

    func testComputeLimForOneBtcAt16PerBtc() throws {
        let lim = try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(lim, BigInt(1_600_000_000))
    }

    func testComputeLimForHalfBtcAt16PerBtc() throws {
        let lim = try computeLim(sourceAmount: BigInt(50_000_000), sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(lim, BigInt(800_000_000))
    }

    func testComputeLimForOneBtcAt6000PerBtc() throws {
        let lim = try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: 6000)
        XCTAssertEqual(lim, BigInt(600_000_000_000))
    }

    // MARK: - computeLim — fractional prices

    func testComputeLimForOneEthAt00625PerEth() throws {
        let lim = try computeLim(
            sourceAmount: BigInt("1000000000000000000"),
            sourceDecimals: 18,
            targetPrice: Decimal(string: "0.0625")!
        )
        XCTAssertEqual(lim, BigInt(6_250_000))
    }

    func testComputeLimForFiftyKUsdtAt000001PerUsdt() throws {
        let lim = try computeLim(
            sourceAmount: BigInt(50_000_000_000),
            sourceDecimals: 6,
            targetPrice: Decimal(string: "0.00001")!
        )
        XCTAssertEqual(lim, BigInt(50_000_000))
    }

    // MARK: - computeLim — edge cases

    func testComputeLimForVerySmallPriceProducesOne() throws {
        // 1 BTC at 0.00000001 target/source → 0.00000001 target → LIM = 1 (1e8 fixed-point)
        let lim = try computeLim(
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetPrice: Decimal(string: "0.00000001")!
        )
        XCTAssertEqual(lim, BigInt(1))
    }

    func testComputeLimForVeryLargePrice() throws {
        // 1 BTC at 1_000_000 target/source → 1_000_000 target → LIM = 1e14
        let lim = try computeLim(
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetPrice: 1_000_000
        )
        XCTAssertEqual(lim, BigInt("100000000000000"))
    }

    func testComputeLimTruncatesPriceBeyondEightDecimalPlaces() throws {
        // targetPrice = 16.123456789 (9 dp); should truncate to 16.12345678 in 1e8 fixed-point
        // → LIM = 1_612_345_678 (not 1_612_345_678.9, not 0)
        let lim = try computeLim(
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetPrice: Decimal(string: "16.123456789")!
        )
        XCTAssertEqual(lim, BigInt(1_612_345_678))
    }

    func testComputeLimZeroSourceAmountReturnsZero() throws {
        let lim = try computeLim(sourceAmount: 0, sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(lim, BigInt(0))
    }

    // MARK: - computeLim — overflow MUST fail loud (fund-safety)

    func testComputeLimOverflowingTargetPriceThrowsInsteadOfYieldingZero() {
        // A `targetPrice` near `Decimal.greatestFiniteMagnitude` (~1e127)
        // overflows when scaled by 1e8. The old code did `BigInt("NaN") ?? 0`,
        // silently emitting LIM=0 — which THORChain reads as "fill at ANY
        // price", the OPPOSITE of a limit order. We must THROW, never return 0.
        let huge = Decimal.greatestFiniteMagnitude
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: huge)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .targetPriceOverflow)
        }
    }

    func testComputeLimOverflowNeverSilentlyProducesZero() throws {
        // Belt-and-suspenders: assert no overflow path returns 0. If it didn't
        // throw, it must be a genuine non-zero value.
        let huge = Decimal.greatestFiniteMagnitude
        do {
            let lim = try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: huge)
            XCTAssertNotEqual(lim, BigInt(0), "Overflow must never silently yield LIM=0")
        } catch {
            XCTAssertEqual(error as? LimitSwapMemoError, .targetPriceOverflow)
        }
    }

    // MARK: - computeLim — underflow MUST fail loud (fund-safety)

    func testComputeLimUnderflowingToZeroWithPositiveInputsThrows() {
        // 1 wei source (18 decimals) at price 1 scales to LIM = 1e8 / 1e18, which
        // truncates to 0. Both inputs are positive, so a `LIM=0` memo ("fill at
        // ANY price") would be a fund-safety hazard — must THROW, not return 0.
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(1), sourceDecimals: 18, targetPrice: 1)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    func testComputeLimUnderflowFromTinyPriceThrows() {
        // Dust output from a very low target price against a high-decimal source.
        XCTAssertThrowsError(
            try computeLim(
                sourceAmount: BigInt(1),
                sourceDecimals: 18,
                targetPrice: Decimal(string: "0.0001")!
            )
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    func testComputeLimStillReturnsZeroForZeroSourceAmount() throws {
        // A zero source amount is a separate precondition (rejected upstream by
        // validation), not the positive-input underflow the guard targets — it
        // must keep returning 0 without throwing.
        let lim = try computeLim(sourceAmount: 0, sourceDecimals: 18, targetPrice: 1)
        XCTAssertEqual(lim, BigInt(0))
    }

    // MARK: - computeLim — negative inputs MUST fail loud (fund-safety)

    func testComputeLimNegativeSourceAmountThrows() {
        // A negative source amount would produce a NEGATIVE LIM that slips past
        // the `lim <= 0` underflow guard (which requires both inputs positive).
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(-100_000_000), sourceDecimals: 8, targetPrice: 16)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    func testComputeLimNegativeTargetPriceThrows() {
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: -16)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    func testComputeLimNegativeBothInputsThrows() {
        XCTAssertThrowsError(
            try computeLim(
                sourceAmount: BigInt(-100_000_000),
                sourceDecimals: 8,
                targetPrice: Decimal(string: "-0.5")!
            )
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    // MARK: - limitOrderExpectedOutput (Verify / Done display amount)

    func testLimitOrderExpectedOutputForOneBtcAt16() {
        let out = limitOrderExpectedOutput(
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetPrice: 16
        )
        XCTAssertEqual(out, Decimal(16))
    }

    func testLimitOrderExpectedOutputForFractionalPrice() {
        let out = limitOrderExpectedOutput(
            sourceAmount: BigInt("1000000000000000000"),
            sourceDecimals: 18,
            targetPrice: Decimal(string: "0.0625")!
        )
        XCTAssertEqual(out, Decimal(string: "0.0625")!)
    }

    func testLimitOrderExpectedOutputForZeroSourceIsZero() {
        let out = limitOrderExpectedOutput(sourceAmount: 0, sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(out, Decimal(0))
    }

    // MARK: - computeExpiryBlocks

    func testComputeExpiryBlocksFor12Hours() {
        XCTAssertEqual(computeExpiryBlocks(hours: 12), 7200)
    }

    func testComputeExpiryBlocksFor24Hours() {
        XCTAssertEqual(computeExpiryBlocks(hours: 24), 14400)
    }

    func testComputeExpiryBlocksFor72Hours() {
        XCTAssertEqual(computeExpiryBlocks(hours: 72), 43200)
    }

    func testComputeExpiryBlocksScalesByThorchainBlockRate() {
        // Sanity: any hour count × 600 (THORChain blocks per hour at 6s blocks)
        XCTAssertEqual(computeExpiryBlocks(hours: 1), 600)
    }

    // MARK: - computePresetPrice

    func testPresetPriceMarket() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: 0), 100)
    }

    func testPresetPricePlusOnePercent() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: 1), 101)
    }

    func testPresetPricePlusFivePercent() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: 5), 105)
    }

    func testPresetPricePlusTenPercent() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: 10), 110)
    }

    func testPresetPriceWithFractionalMarket() {
        // 0.0625 × 1.05 = 0.065625
        XCTAssertEqual(computePresetPrice(marketPrice: Decimal(string: "0.0625")!, pctAboveMarket: 5), Decimal(string: "0.065625")!)
    }

    // MARK: - computePctFromMarket

    func testPctFromMarketAtMarket() {
        XCTAssertEqual(computePctFromMarket(targetPrice: 100, marketPrice: 100), 0)
    }

    func testPctFromMarketFivePercentAbove() {
        XCTAssertEqual(computePctFromMarket(targetPrice: 105, marketPrice: 100), 5)
    }

    func testPctFromMarketTenPercentBelow() {
        XCTAssertEqual(computePctFromMarket(targetPrice: 90, marketPrice: 100), -10)
    }

    func testPctFromMarketZeroMarketReturnsZero() {
        // Guard against divide-by-zero in degenerate cases.
        XCTAssertEqual(computePctFromMarket(targetPrice: 5, marketPrice: 0), 0)
    }

    // MARK: - evaluateWarning

    func testWarningWhenTargetEqualsMarket() {
        XCTAssertEqual(evaluateWarning(targetPrice: 100, marketPrice: 100), .priceAtOrBelowMarket)
    }

    func testWarningWhenTargetBelowMarket() {
        XCTAssertEqual(evaluateWarning(targetPrice: 95, marketPrice: 100), .priceAtOrBelowMarket)
    }

    func testNoWarningWhenTargetSlightlyAboveMarket() {
        XCTAssertNil(evaluateWarning(targetPrice: 105, marketPrice: 100))
    }

    func testNoWarningAtTwentyPercentBoundary() {
        // 1.2× exactly should NOT trigger the "may not fill" warning — only > 1.2×
        XCTAssertNil(evaluateWarning(targetPrice: 120, marketPrice: 100))
    }

    func testWarningWhenTargetWellAboveMarket() {
        XCTAssertEqual(evaluateWarning(targetPrice: 121, marketPrice: 100), .priceFarAboveMarket)
    }

    func testWarningWhenTargetTwiceMarket() {
        XCTAssertEqual(evaluateWarning(targetPrice: 200, marketPrice: 100), .priceFarAboveMarket)
    }
}
