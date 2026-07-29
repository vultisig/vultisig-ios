//
//  MarketChartTests.swift
//  VultisigAppTests
//
//  Decoding of CoinGecko's `[[msEpoch, price]]` array-of-arrays, the
//  sparse-series floor, the flat-series y-domain, the resampler's contract and
//  the per-range `days` mapping.
//

@testable import VultisigApp
import Foundation
import XCTest

final class MarketChartTests: XCTestCase {

    // MARK: - Decoding

    func testDecodesWellFormedSeriesInOrder() throws {
        let json = Data(#"{"prices":[[1000,10.5],[2000,11.25],[3000,12.0]]}"#.utf8)
        let chart = try JSONDecoder().decode(MarketChart.self, from: json)

        XCTAssertEqual(chart.points.count, 3)
        XCTAssertEqual(chart.points[0].date, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(chart.points[0].price, 10.5)
        XCTAssertEqual(chart.points[2].price, 12.0)
    }

    func testDecodeIgnoresExtraSeriesInThePayload() throws {
        // The live payload also carries `market_caps` / `total_volumes`; the
        // model reads only `prices` and must not trip over the rest.
        let json = Data(#"""
        {"prices":[[1000,1.0],[2000,2.0]],"market_caps":[[1000,9.0]],"total_volumes":[[1000,8.0]]}
        """#.utf8)
        let chart = try JSONDecoder().decode(MarketChart.self, from: json)

        XCTAssertEqual(chart.points.count, 2)
    }

    func testDecodeDropsShortAndEmptyInnerArrays() throws {
        let json = Data(#"{"prices":[[1000,10.0],[2000],[],[3000,12.0]]}"#.utf8)
        let chart = try JSONDecoder().decode(MarketChart.self, from: json)

        XCTAssertEqual(chart.points.count, 2)
        XCTAssertEqual(chart.points.map(\.price), [10.0, 12.0])
    }

    func testDecodeDropsNullSamplesInsteadOfFailingTheSeries() throws {
        let json = Data(#"{"prices":[[1000,10.0],[2000,null],[null,11.0],[3000,12.0]]}"#.utf8)
        let chart = try JSONDecoder().decode(MarketChart.self, from: json)

        XCTAssertEqual(chart.points.map(\.price), [10.0, 12.0])
    }

    func testDecodeCollapsesRepeatedTimestampsToTheLastValue() throws {
        // Two samples at one instant are not something a price line can draw,
        // and a zero-length interval has nothing to interpolate across when the
        // series is resampled onto a time grid.
        let json = Data(#"{"prices":[[1000,10.0],[2000,11.0],[2000,11.5],[3000,12.0]]}"#.utf8)
        let chart = try JSONDecoder().decode(MarketChart.self, from: json)

        XCTAssertEqual(chart.points.map(\.price), [10.0, 11.5, 12.0])
        XCTAssertEqual(Set(chart.points.map(\.date)).count, chart.points.count)
    }

    func testDecodeSortsOutOfOrderTimestamps() throws {
        let json = Data(#"{"prices":[[3000,12.0],[1000,10.0],[2000,11.0]]}"#.utf8)
        let chart = try JSONDecoder().decode(MarketChart.self, from: json)

        XCTAssertEqual(chart.points.map(\.price), [10.0, 11.0, 12.0])
    }

    func testDecodesEmptySeries() throws {
        let json = Data(#"{"prices":[]}"#.utf8)
        let chart = try JSONDecoder().decode(MarketChart.self, from: json)

        XCTAssertTrue(chart.points.isEmpty)
        XCTAssertFalse(chart.isUsable)
        XCTAssertNil(chart.changeFraction)
    }

    func testDecodeThrowsWhenPricesKeyIsMissing() {
        let json = Data(#"{"market_caps":[[1000,1.0]]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MarketChart.self, from: json))
    }

    // MARK: - Usability floor

    func testSeriesBelowTheFloorIsNotUsable() {
        let chart = Self.makeChart(count: MarketChart.minimumUsablePoints - 1)
        XCTAssertFalse(chart.isUsable)
    }

    func testSeriesAtTheFloorIsUsable() {
        let chart = Self.makeChart(count: MarketChart.minimumUsablePoints)
        XCTAssertTrue(chart.isUsable)
    }

    // MARK: - Change

    func testChangeFractionIsSignedByDirection() {
        let rising = MarketChart(points: [
            MarketChartPoint(date: Date(timeIntervalSince1970: 0), price: 100),
            MarketChartPoint(date: Date(timeIntervalSince1970: 60), price: 110)
        ])
        XCTAssertEqual(try XCTUnwrap(rising.changeFraction), 0.1, accuracy: 0.0001)

        let falling = MarketChart(points: [
            MarketChartPoint(date: Date(timeIntervalSince1970: 0), price: 100),
            MarketChartPoint(date: Date(timeIntervalSince1970: 60), price: 90)
        ])
        XCTAssertEqual(try XCTUnwrap(falling.changeFraction), -0.1, accuracy: 0.0001)
    }

    func testChangeFractionIsNilWhenTheWindowOpensAtZero() {
        let chart = MarketChart(points: [
            MarketChartPoint(date: Date(timeIntervalSince1970: 0), price: 0),
            MarketChartPoint(date: Date(timeIntervalSince1970: 60), price: 5)
        ])
        XCTAssertNil(chart.changeFraction)
    }

    // MARK: - Domain

    func testFlatSeriesGetsAPaddedDomain() {
        let chart = MarketChart(points: (0..<20).map {
            MarketChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0)), price: 1.0)
        })
        let domain = chart.priceDomain

        XCTAssertLessThan(domain.lowerBound, 1.0)
        XCTAssertGreaterThan(domain.upperBound, 1.0)
    }

    func testMovingSeriesDomainLeavesHeadroomAroundItsBounds() {
        let chart = MarketChart(points: [
            MarketChartPoint(date: Date(timeIntervalSince1970: 0), price: 5),
            MarketChartPoint(date: Date(timeIntervalSince1970: 60), price: 15)
        ])

        // Span 10, headroom 8% ⇒ 0.8 either side, so the stroke at the high and
        // low is not clipped by the plot's edge.
        XCTAssertEqual(chart.priceDomain.lowerBound, 4.2, accuracy: 0.0001)
        XCTAssertEqual(chart.priceDomain.upperBound, 15.8, accuracy: 0.0001)
    }

    func testDomainAlwaysContainsEverySample() {
        let chart = Self.makeChart(count: 50)
        let domain = chart.priceDomain

        for point in chart.points {
            XCTAssertTrue(domain.contains(point.price))
        }
    }

    func testAllZeroSeriesStillGetsANonDegenerateDomain() {
        let chart = MarketChart(points: (0..<5).map {
            MarketChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0)), price: 0)
        })
        XCTAssertLessThan(chart.priceDomain.lowerBound, chart.priceDomain.upperBound)
    }

    // MARK: - Resampling

    func testResamplingHitsTheTargetCountFromEveryDirection() {
        // The live counts the five ranges come back with, plus the target
        // itself. All of them have to land on the same cardinality or a range
        // switch cannot morph mark-for-mark.
        for sourceCount in [169, 200, 289, 366, 721, 4838] {
            let resampled = Self.makeChart(count: sourceCount).resampled(to: 200)
            XCTAssertEqual(resampled.points.count, 200, "resampling \(sourceCount)")
        }
    }

    func testResamplingPreservesFirstAndLastPointExactly() {
        for sourceCount in [169, 289, 4838] {
            let chart = Self.makeChart(count: sourceCount)
            let resampled = chart.resampled(to: 200)

            XCTAssertEqual(resampled.points.first, chart.points.first)
            XCTAssertEqual(resampled.points.last, chart.points.last)
        }
    }

    func testResamplingPreservesTheWindowChange() throws {
        // The percentage on the card is read off the endpoints, so it has to
        // survive the resample untouched in both directions.
        for sourceCount in [169, 4838] {
            let chart = Self.makeChart(count: sourceCount)
            let before = try XCTUnwrap(chart.changeFraction)
            let after = try XCTUnwrap(chart.resampled(to: 200).changeFraction)

            XCTAssertEqual(before, after, accuracy: 1e-12)
        }
    }

    func testUpsamplingInterpolatesRatherThanRepeating() {
        let chart = MarketChart(points: [
            MarketChartPoint(date: Date(timeIntervalSince1970: 0), price: 0),
            MarketChartPoint(date: Date(timeIntervalSince1970: 100), price: 100)
        ])
        let resampled = chart.resampled(to: 5)

        XCTAssertEqual(resampled.points.map(\.price), [0, 25, 50, 75, 100])
        XCTAssertEqual(
            resampled.points.map(\.date.timeIntervalSince1970),
            [0, 25, 50, 75, 100]
        )
    }

    func testResamplingKeepsAscendingOrder() {
        for sourceCount in [11, 169, 2000] {
            let dates = Self.makeChart(count: sourceCount).resampled(to: 200).points.map(\.date)
            XCTAssertEqual(dates, dates.sorted())
            XCTAssertEqual(Set(dates).count, dates.count)
        }
    }

    func testResamplingAnAlreadyRegularSeriesReproducesIt() {
        // Same count, already evenly spaced in time: the grid lands back on the
        // samples it came from.
        let chart = Self.makeChart(count: 200)
        let resampled = chart.resampled(to: 200)

        XCTAssertEqual(resampled.points.count, chart.points.count)
        for (original, sample) in zip(chart.points, resampled.points) {
            XCTAssertEqual(sample.price, original.price, accuracy: 1e-9)
            XCTAssertEqual(
                sample.date.timeIntervalSince1970,
                original.date.timeIntervalSince1970,
                accuracy: 1e-6
            )
        }
    }

    func testResamplingSpreadsTheGridOverElapsedTimeNotOverTheArray() {
        // A gap in the upstream samples must stay a gap: the plot's x is the
        // sample's index, so a grid laid out over the array would give six
        // silent hours the same width as the minute either side of them, and
        // move the price action to a time it did not happen at.
        let chart = MarketChart(points: [
            MarketChartPoint(date: Date(timeIntervalSince1970: 0), price: 100),
            MarketChartPoint(date: Date(timeIntervalSince1970: 60), price: 100),
            MarketChartPoint(date: Date(timeIntervalSince1970: 21_660), price: 200)
        ])
        let resampled = chart.resampled(to: 5)

        // Evenly spaced in time, not one sample per source interval.
        XCTAssertEqual(
            resampled.points.map(\.date.timeIntervalSince1970),
            [0, 5415, 10_830, 16_245, 21_660]
        )
        // The climb happens across the long interval, so the midpoint of the
        // window is halfway up it — not already at the top, which is where an
        // index-spaced grid would have put it.
        XCTAssertEqual(resampled.points[2].price, 150, accuracy: 0.5)
    }

    func testResamplingLeavesADegenerateSeriesAlone() {
        // Nothing to interpolate between: a series this short is below the
        // usability floor and never reaches the chart anyway, but the
        // resampler must not invent a line out of it.
        let single = MarketChart(points: [
            MarketChartPoint(date: Date(timeIntervalSince1970: 0), price: 7)
        ])
        XCTAssertEqual(single.resampled(to: 200).points.count, 1)
        XCTAssertTrue(MarketChart(points: []).resampled(to: 200).points.isEmpty)
    }

    func testResamplingToFewerThanTwoSamplesIsANoOp() {
        // Below two there is no line to draw, so the series comes back
        // untouched rather than truncated to something undrawable.
        let chart = Self.makeChart(count: 50)
        for count in [-1, 0, 1] {
            XCTAssertEqual(chart.resampled(to: count).points, chart.points, "count \(count)")
        }
    }

    func testResamplingToTwoKeepsOnlyTheEndpoints() {
        let chart = Self.makeChart(count: 50)
        let resampled = chart.resampled(to: 2)

        XCTAssertEqual(resampled.points, [chart.points.first, chart.points.last].compactMap { $0 })
    }

    // MARK: - Range

    func testRangeDaysMapping() {
        XCTAssertEqual(MarketChartRange.day.days, "1")
        XCTAssertEqual(MarketChartRange.week.days, "7")
        XCTAssertEqual(MarketChartRange.month.days, "30")
        XCTAssertEqual(MarketChartRange.year.days, "365")
        XCTAssertEqual(MarketChartRange.all.days, "max")
    }

    func testShortRangesRefreshMoreOftenThanLongOnes() {
        XCTAssertLessThan(MarketChartRange.day.cacheTTL, MarketChartRange.week.cacheTTL)
        XCTAssertLessThan(MarketChartRange.month.cacheTTL, MarketChartRange.year.cacheTTL)
        XCTAssertEqual(MarketChartRange.year.cacheTTL, MarketChartRange.all.cacheTTL)
    }

    func testAllRangesAreSelectableAndUniquelyIdentified() {
        let ids = MarketChartRange.allCases.map(\.id)
        XCTAssertEqual(ids.count, 5)
        XCTAssertEqual(Set(ids).count, 5)
    }

    // MARK: - Helpers

    private static func makeChart(count: Int) -> MarketChart {
        MarketChart(points: (0..<count).map { index in
            MarketChartPoint(
                date: Date(timeIntervalSince1970: TimeInterval(index) * 300),
                price: 100 + Double(index)
            )
        })
    }
}
