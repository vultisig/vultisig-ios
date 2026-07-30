//
//  LimitPairSeriesTests.swift
//  VultisigAppTests
//
//  The pair-ratio series: the shared-grid contract, the windows it refuses,
//  and the interpolation in between.
//

@testable import VultisigApp
import Foundation
import XCTest

final class LimitPairSeriesTests: XCTestCase {

    /// A series of `count` evenly spaced samples starting at `start` seconds,
    /// one sample every 10 seconds, priced by `price(secondsFromEpoch)`.
    private func makeChart(
        start: TimeInterval,
        count: Int = 11,
        step: TimeInterval = 10,
        price: (TimeInterval) -> Double
    ) -> MarketChart {
        MarketChart(points: (0..<count).map { index in
            let seconds = start + Double(index) * step
            return MarketChartPoint(date: Date(timeIntervalSince1970: seconds), price: price(seconds))
        })
    }

    // MARK: - The quotient itself

    func testRatioOfFlatSeriesIsTheQuotient() throws {
        let base = makeChart(start: 0) { _ in 30_000 }
        let quote = makeChart(start: 0) { _ in 1_000 }

        let ratio = try XCTUnwrap(LimitPairSeries.ratio(base: base, quote: quote))

        XCTAssertEqual(ratio.points.count, MarketChartRendering.pointCount)
        for point in ratio.points {
            XCTAssertEqual(point.price, 30, accuracy: 1e-9)
        }
    }

    func testInterpolatesBetweenObservations() throws {
        // Base rises linearly with time, quote is flat at 2 — so the ratio at
        // any instant is that instant's price halved, including at instants no
        // sample was actually taken at. Priced at `t + 10` rather than `t` so
        // the opening sample is a legal price: a series containing a zero is
        // refused outright, which is a different test.
        let base = makeChart(start: 0) { $0 + 10 }
        let quote = makeChart(start: 0) { _ in 2 }

        let ratio = try XCTUnwrap(LimitPairSeries.ratio(base: base, quote: quote, count: 3))

        XCTAssertEqual(ratio.points[0].price, 5, accuracy: 1e-9)    // t = 0   → 10 / 2
        XCTAssertEqual(ratio.points[1].price, 30, accuracy: 1e-9)   // t = 50  → 60 / 2
        XCTAssertEqual(ratio.points[2].price, 55, accuracy: 1e-9)   // t = 100 → 110 / 2
    }

    func testHonoursTheRequestedSampleCount() throws {
        let base = makeChart(start: 0) { $0 + 1 }
        let quote = makeChart(start: 0) { _ in 1 }

        let ratio = try XCTUnwrap(LimitPairSeries.ratio(base: base, quote: quote, count: 37))

        XCTAssertEqual(ratio.points.count, 37)
    }

    // MARK: - The shared grid

    func testSamplesOnlyTheOverlappingWindow() throws {
        let base = makeChart(start: 0) { _ in 100 }        // 0 … 100
        let quote = makeChart(start: 20) { _ in 4 }        // 20 … 120

        let ratio = try XCTUnwrap(LimitPairSeries.ratio(base: base, quote: quote))

        XCTAssertEqual(ratio.points.first?.date, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(ratio.points.last?.date, Date(timeIntervalSince1970: 100))
    }

    func testDividesPricesObservedAtTheSameInstant() throws {
        // The regression this type exists for. Base is priced from its own
        // timestamp and opens at t = 0; quote opens at t = 20. Resampling each
        // series independently and dividing position-by-position would pair
        // base's opening sample (t = 0, price 10) with quote's (t = 20), giving
        // a first ratio of 2.5. On a shared grid the first sample is at t = 20
        // on BOTH sides, so it is 30 / 4.
        let base = makeChart(start: 0) { $0 + 10 }
        let quote = makeChart(start: 20) { _ in 4 }

        let ratio = try XCTUnwrap(LimitPairSeries.ratio(base: base, quote: quote))

        XCTAssertEqual(ratio.points.first?.price ?? .nan, 7.5, accuracy: 1e-9)
        XCTAssertEqual(ratio.points.last?.price ?? .nan, 27.5, accuracy: 1e-9)
    }

    func testTracksAStepInTheQuoteSeriesAtTheInstantItHappens() throws {
        // Quote doubles halfway through the window; the ratio must halve from
        // that instant, not from the middle of the array.
        let base = makeChart(start: 0) { _ in 100 }
        let quote = makeChart(start: 0) { $0 < 50 ? 1 : 2 }

        let ratio = try XCTUnwrap(LimitPairSeries.ratio(base: base, quote: quote, count: 11))

        XCTAssertEqual(ratio.points[0].price, 100, accuracy: 1e-9)
        XCTAssertEqual(ratio.points[4].price, 100, accuracy: 1e-9)   // t = 40, still 1
        XCTAssertEqual(ratio.points[10].price, 50, accuracy: 1e-9)   // t = 100, now 2
    }

    // MARK: - Series it refuses

    func testReturnsNilWhenWindowsDoNotOverlap() {
        let base = makeChart(start: 0) { _ in 10 }          // 0 … 100
        let quote = makeChart(start: 500) { _ in 1 }        // 500 … 600

        XCTAssertNil(LimitPairSeries.ratio(base: base, quote: quote))
    }

    func testReturnsNilWhenWindowsTouchAtASingleInstant() {
        // A zero-width overlap has no grid to lay out — every sample would be
        // the same instant.
        let base = makeChart(start: 0) { _ in 10 }          // 0 … 100
        let quote = makeChart(start: 100) { _ in 1 }        // 100 … 200

        XCTAssertNil(LimitPairSeries.ratio(base: base, quote: quote))
    }

    func testReturnsNilWhenEitherSeriesIsTooSparseToDraw() {
        let sparse = makeChart(start: 0, count: MarketChart.minimumUsablePoints - 1) { _ in 10 }
        let dense = makeChart(start: 0, count: 40) { _ in 1 }

        XCTAssertNil(LimitPairSeries.ratio(base: sparse, quote: dense))
        XCTAssertNil(LimitPairSeries.ratio(base: dense, quote: sparse))
        XCTAssertNotNil(LimitPairSeries.ratio(base: dense, quote: dense))
    }

    func testReturnsNilWhenEitherSideCarriesANonPositivePrice() {
        // The regression behind the source-sample guard. A lone zero at t=50 is
        // not landed on by the output grid, so interpolation turns it into a run
        // of near-zero divisors and the ratio spikes to ~40× the true value
        // instead of tripping any check on the quotient.
        let flat = makeChart(start: 0) { _ in 100 }
        let zeroed = makeChart(start: 0) { $0 == 50 ? 0 : 1 }
        let negative = makeChart(start: 0) { $0 == 50 ? -1 : 1 }

        XCTAssertNil(LimitPairSeries.ratio(base: flat, quote: zeroed))
        XCTAssertNil(LimitPairSeries.ratio(base: flat, quote: negative))
        XCTAssertNil(LimitPairSeries.ratio(base: zeroed, quote: flat))
        XCTAssertNil(LimitPairSeries.ratio(base: negative, quote: flat))
    }

    func testAcceptsASmallButPositivePriceRatherThanTreatingItAsBad() throws {
        // The rule is "not positive", not "small". A genuinely cheap quote asset
        // gives a genuinely large ratio, and that is the truth about the pair.
        let base = makeChart(start: 0) { _ in 100 }
        let cheap = makeChart(start: 0) { _ in 0.001 }

        let ratio = try XCTUnwrap(LimitPairSeries.ratio(base: base, quote: cheap))

        XCTAssertEqual(ratio.points.first?.price ?? .nan, 100_000, accuracy: 1e-6)
    }

    func testReturnsNilForADegenerateSampleCount() {
        let base = makeChart(start: 0) { _ in 100 }
        let quote = makeChart(start: 0) { _ in 1 }

        XCTAssertNil(LimitPairSeries.ratio(base: base, quote: quote, count: 1))
        XCTAssertNil(LimitPairSeries.ratio(base: base, quote: quote, count: 0))
    }
}
