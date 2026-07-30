//
//  LimitPriceChartLayoutTests.swift
//  VultisigAppTests
//
//  The chart's derived geometry — the single place values that Charts cannot
//  render are screened out, and where the off-scale treatment is decided.
//

@testable import VultisigApp
import Foundation
import XCTest

final class LimitPriceChartLayoutTests: XCTestCase {

    private typealias Layout = LimitPriceChartView.Layout

    private func makeChart(prices: [Double]) -> MarketChart {
        MarketChart(points: prices.enumerated().map { index, price in
            MarketChartPoint(date: Date(timeIntervalSince1970: Double(index) * 60), price: price)
        })
    }

    private var calmChart: MarketChart {
        makeChart(prices: (0..<40).map { 98 + Double($0 % 5) * 0.4 })
    }

    // MARK: - Values Charts cannot draw

    func testNonFiniteSamplesNeverReachTheMarks() {
        // Filtering them only while computing the domain is not enough: the same
        // points are handed to AreaMark and LineMark, where an infinity fails
        // layout.
        let poisoned = makeChart(prices: [98, 99, .infinity, 100, -.infinity] + Array(repeating: 99.0, count: 20))
        let layout = Layout(chart: poisoned, market: 100, target: 105)

        XCTAssertTrue(layout.points.allSatisfy(\.price.isFinite))
        XCTAssertEqual(layout.points.count, 23)
    }

    func testANonFiniteTargetDrawsNoTargetLineAtAll() {
        // `min(max(nan, lo), hi)` is still nan — clamping does not sanitise it,
        // so the target rule and the band have to be suppressed instead.
        for target in [Double.nan, .infinity, -.infinity] {
            let layout = Layout(chart: calmChart, market: 100, target: target)

            XCTAssertNil(layout.drawnTarget, "target \(target) should not be drawn")
            XCTAssertNil(layout.bandBounds)
        }
    }

    func testANonFiniteMarketIsTreatedAsNoMarketAtAll() {
        for market in [Double.nan, .infinity, 0, -5] {
            let layout = Layout(chart: calmChart, market: market, target: 105)

            XCTAssertNil(layout.market, "market \(market) should not anchor anything")
            XCTAssertNil(layout.bandBounds)
            XCTAssertTrue(layout.guideLevels.isEmpty)
        }
    }

    // MARK: - Off-scale

    func testAnInRangeTargetIsDrawnWhereItIs() {
        let layout = Layout(chart: calmChart, market: 100, target: 105)

        XCTAssertEqual(layout.drawnTarget, 105)
        XCTAssertFalse(layout.isOffScale)
    }

    func testAnOffScaleTargetPinsToTheEdgeAndSaysSo() {
        let layout = Layout(chart: calmChart, market: 100, target: 400)

        XCTAssertTrue(layout.isOffScale)
        XCTAssertTrue(layout.isPinnedToTop)
        XCTAssertEqual(layout.drawnTarget, layout.domain.upperBound)
    }

    func testAnOffScaleTargetBelowTheFloorPinsDownwards() {
        let layout = Layout(chart: calmChart, market: 100, target: 1)

        XCTAssertTrue(layout.isOffScale)
        XCTAssertFalse(layout.isPinnedToTop)
        XCTAssertEqual(layout.drawnTarget, layout.domain.lowerBound)
    }

    // MARK: - Band

    func testTheBandSpansMarketToTargetInEitherDirection() {
        let above = Layout(chart: calmChart, market: 100, target: 105)
        XCTAssertEqual(above.bandBounds, 100...105)

        let below = Layout(chart: calmChart, market: 100, target: 98)
        XCTAssertEqual(below.bandBounds, 98...100)
    }

    func testNoBandOnceTheTargetIsOffScale() {
        // The band's top edge would be the plot's edge rather than the target,
        // so filling it would state a distance that is not the real one. The
        // pinned line and its label carry the magnitude instead.
        let layout = Layout(chart: calmChart, market: 100, target: 400)

        XCTAssertTrue(layout.isOffScale)
        XCTAssertNil(layout.bandBounds)
    }

    func testTheBandIsNeverInverted() {
        // RectangleMark with yStart above yEnd is not a shape Charts can draw.
        for target in stride(from: 60.0, through: 200.0, by: 2.5) {
            let layout = Layout(chart: calmChart, market: 100, target: target)
            guard let bounds = layout.bandBounds else { continue }
            XCTAssertFalse(layout.isOffScale, "an off-scale target must not carry a band")
            XCTAssertLessThanOrEqual(bounds.lowerBound, bounds.upperBound)
        }
    }

    // MARK: - Guides

    func testGuidesSitAtThePresetStopsAndInsideThePlot() {
        let layout = Layout(chart: calmChart, market: 100, target: 100.5)

        // Compared with a tolerance rather than exactly: `100 * (1 + 10/100)`
        // is 110.00000000000001, and a guide's job is to land on a pixel, not
        // to be a decimal literal.
        XCTAssertEqual(layout.guideLevels.count, 2)
        XCTAssertEqual(layout.guideLevels.first ?? .nan, 105, accuracy: 1e-9)
        XCTAssertEqual(layout.guideLevels.last ?? .nan, 110, accuracy: 1e-9)
    }

    func testAGuideIsDroppedWhenTheTargetWouldDrawOverIt() {
        let layout = Layout(chart: calmChart, market: 100, target: 105)

        XCTAssertEqual(layout.guideLevels.count, 1)
        XCTAssertEqual(layout.guideLevels.first ?? .nan, 110, accuracy: 1e-9)
    }
}
