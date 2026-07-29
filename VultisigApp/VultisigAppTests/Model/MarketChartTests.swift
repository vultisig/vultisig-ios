//
//  MarketChartTests.swift
//  VultisigAppTests
//
//  Decoding of CoinGecko's `[[msEpoch, price]]` array-of-arrays, the
//  sparse-series floor, the flat-series y-domain, the downsampler bounds and
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

    func testMovingSeriesUsesItsOwnBounds() {
        let chart = MarketChart(points: [
            MarketChartPoint(date: Date(timeIntervalSince1970: 0), price: 5),
            MarketChartPoint(date: Date(timeIntervalSince1970: 60), price: 15)
        ])
        XCTAssertEqual(chart.priceDomain.lowerBound, 5)
        XCTAssertEqual(chart.priceDomain.upperBound, 15)
    }

    func testAllZeroSeriesStillGetsANonDegenerateDomain() {
        let chart = MarketChart(points: (0..<5).map {
            MarketChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0)), price: 0)
        })
        XCTAssertLessThan(chart.priceDomain.lowerBound, chart.priceDomain.upperBound)
    }

    // MARK: - Downsampling

    func testDownsamplingNeverExceedsTheCap() {
        let chart = Self.makeChart(count: 4838)
        let thinned = chart.downsampled(to: 300)

        XCTAssertLessThanOrEqual(thinned.points.count, 300)
        XCTAssertGreaterThan(thinned.points.count, 250)
    }

    func testDownsamplingPreservesFirstAndLastPoint() {
        let chart = Self.makeChart(count: 4838)
        let thinned = chart.downsampled(to: 300)

        XCTAssertEqual(thinned.points.first, chart.points.first)
        XCTAssertEqual(thinned.points.last, chart.points.last)
    }

    func testDownsamplingKeepsShortSeriesIntact() {
        let chart = Self.makeChart(count: 120)
        XCTAssertEqual(chart.downsampled(to: 300).points, chart.points)
    }

    func testDownsamplingKeepsAscendingOrder() {
        let thinned = Self.makeChart(count: 2000).downsampled(to: 300)
        let dates = thinned.points.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testDownsamplingIsANoOpForAnAbsurdlySmallCap() {
        let chart = Self.makeChart(count: 500)
        XCTAssertEqual(chart.downsampled(to: 2).points, chart.points)
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
