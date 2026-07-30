//
//  LimitChartDomainTests.swift
//  VultisigAppTests
//
//  The market-anchored y-domain and the off-scale predicate, plus the reach
//  verdict the hint line under the chart is built from.
//

@testable import VultisigApp
import Foundation
import XCTest

final class LimitChartDomainTests: XCTestCase {

    private func makeChart(prices: [Double]) -> MarketChart {
        MarketChart(points: prices.enumerated().map { index, price in
            MarketChartPoint(date: Date(timeIntervalSince1970: Double(index) * 60), price: price)
        })
    }

    /// A calm series that sits just under the market price — the common case.
    private var calmChart: MarketChart {
        makeChart(prices: (0..<40).map { 98 + Double($0 % 5) * 0.4 })
    }

    // MARK: - Domain

    func testCeilingIsThePresetsReachWhenTheSeriesIsCalm() {
        let domain = LimitChartDomain.range(for: calmChart, market: 100)

        // The ceiling comes from 100 × 1.12 and not from the series' own 99.6,
        // so there is somewhere to drag to.
        XCTAssertGreaterThan(domain.upperBound, 112)
        // ...and not from the 1.2× warning threshold, which would waste the plot.
        XCTAssertLessThan(domain.upperBound, 120)
    }

    func testSeriesWidensTheDomainWhenItRunsPastTheAnchors() {
        let volatile = makeChart(prices: [60, 80, 140, 90, 70] + Array(repeating: 100.0, count: 20))
        let domain = LimitChartDomain.range(for: volatile, market: 100)

        XCTAssertLessThan(domain.lowerBound, 60)
        XCTAssertGreaterThan(domain.upperBound, 140)
    }

    func testDomainIsStableAcrossEveryTargetADragCouldProduce() {
        // The property that makes dragging feel like moving a line over a chart
        // rather than zooming one: sweeping the target across (and past) the
        // plot must not move the plot. Target-independence is structural — the
        // function takes no target — so what is worth pinning is that the
        // caller's usage cannot reintroduce a dependence: the same domain is
        // used to place every one of those targets.
        let domain = LimitChartDomain.range(for: calmChart, market: 100)

        for target in stride(from: 50.0, through: 400.0, by: 5.0) {
            XCTAssertEqual(LimitChartDomain.range(for: calmChart, market: 100), domain)
            // ...and the only thing the target decides is whether it is pinned.
            XCTAssertEqual(
                LimitChartDomain.isOffScale(target: target, in: domain),
                !domain.contains(target)
            )
        }
    }

    func testDomainSurvivesANonFiniteSample() {
        // An infinity would make the span infinite and the domain
        // -infinity...+infinity, collapsing the whole plot rather than one point.
        let poisoned = makeChart(prices: [98, 99, .infinity, 100] + Array(repeating: 99.0, count: 20))
        let domain = LimitChartDomain.range(for: poisoned, market: 100)

        XCTAssertTrue(domain.lowerBound.isFinite)
        XCTAssertTrue(domain.upperBound.isFinite)
        XCTAssertTrue(domain.contains(100))
    }

    func testFallsBackToTheDataAnchoredDomainWithoutAMarketReference() {
        // The market probe is async, so the first frames can arrive without one.
        let chart = calmChart

        XCTAssertEqual(LimitChartDomain.range(for: chart, market: nil), chart.priceDomain)
        XCTAssertEqual(LimitChartDomain.range(for: chart, market: 0), chart.priceDomain)
        XCTAssertEqual(LimitChartDomain.range(for: chart, market: -5), chart.priceDomain)
    }

    func testFlatSeriesAtMarketStillGetsAUsableDomain() {
        let flat = makeChart(prices: Array(repeating: 100.0, count: 30))
        let domain = LimitChartDomain.range(for: flat, market: 100)

        XCTAssertLessThan(domain.lowerBound, 100)
        XCTAssertGreaterThan(domain.upperBound, 100)
    }

    // MARK: - Off-scale

    func testOffScaleOnlyOutsideTheDomain() {
        let domain = LimitChartDomain.range(for: calmChart, market: 100)

        XCTAssertFalse(LimitChartDomain.isOffScale(target: 105, in: domain))
        XCTAssertTrue(LimitChartDomain.isOffScale(target: 138, in: domain))
        XCTAssertTrue(LimitChartDomain.isOffScale(target: 1, in: domain))
    }

    // MARK: - Agreement with the form's own thresholds

    func testFarAboveMarketMultipleMatchesTheWarningTheFormRaises() {
        // The chart colours the target line off this constant while the warning
        // row comes from `evaluateWarning`'s own inline threshold. They are two
        // spellings of one rule in two numeric types, so pin them together:
        // just under the multiple must not warn, just over must.
        let market: Decimal = 100
        let multiple = Decimal(LimitChartDomain.farAboveMarketMultiple)

        XCTAssertNil(
            evaluateWarning(targetPrice: market * multiple, marketPrice: market),
            "the multiple itself is the boundary and must not warn"
        )
        XCTAssertEqual(
            evaluateWarning(targetPrice: market * multiple * Decimal(1.001), marketPrice: market),
            .priceFarAboveMarket
        )
    }

    func testAtOrBelowMarketBoundaryMatchesTheFormsWarning() {
        // The reach verdict's below-market shortcut and the form's warning have
        // to agree on the boundary, or the hint and the warning row contradict
        // each other at exactly the market price.
        let chart = calmChart

        XCTAssertEqual(LimitChartReach.evaluate(chart: chart, target: 100, market: 100), .atOrBelowMarket)
        XCTAssertEqual(evaluateWarning(targetPrice: 100, marketPrice: 100), .priceAtOrBelowMarket)
    }

    // MARK: - Reach

    func testReachReportsAtOrBelowMarketOnTheBoundary() {
        let chart = calmChart

        XCTAssertEqual(LimitChartReach.evaluate(chart: chart, target: 100, market: 100), .atOrBelowMarket)
        XCTAssertEqual(LimitChartReach.evaluate(chart: chart, target: 90, market: 100), .atOrBelowMarket)
    }

    func testReachReportsTheMostRecentTouchNotTheFirst() {
        // Price hits 120 early and again late; the useful answer is the late one.
        // Samples are 60s apart: the second 120 is at t=240, and the line falls
        // from 120 to 100 over the following minute, crossing the 115 target a
        // quarter of the way down it.
        let chart = makeChart(prices: [100, 120, 100, 100, 120, 100, 100])
        let verdict = LimitChartReach.evaluate(chart: chart, target: 115, market: 100)

        XCTAssertEqual(verdict, .lastTraded(at: Date(timeIntervalSince1970: 255)))
    }

    func testReachInterpolatesTheCrossingRatherThanReportingTheSample() {
        // Reporting the sample's own timestamp ages the answer by up to one grid
        // step — hours on a month window, over a week on ALL — and disagrees
        // with the crossing the user can see on the plot.
        let chart = makeChart(prices: [120, 100] + Array(repeating: 100.0, count: 20))

        XCTAssertEqual(
            LimitChartReach.evaluate(chart: chart, target: 110, market: 90),
            .lastTraded(at: Date(timeIntervalSince1970: 30))
        )
    }

    func testReachReportsTheFinalSampleWhenTheSeriesEndsAboveTarget() {
        // Nothing follows the last sample to interpolate towards.
        let chart = makeChart(prices: Array(repeating: 100.0, count: 20) + [130])
        let verdict = LimitChartReach.evaluate(chart: chart, target: 125, market: 100)

        XCTAssertEqual(verdict, .lastTraded(at: Date(timeIntervalSince1970: 1200)))
    }

    func testReachReportsTheWindowHighWhenTheTargetWasNeverMet() {
        let chart = makeChart(prices: [100, 104, 99, 101])
        let verdict = LimitChartReach.evaluate(chart: chart, target: 130, market: 100)

        XCTAssertEqual(verdict, .notReached(highest: 104))
    }

    func testReachTreatsAnExactTouchAsReached() {
        let chart = makeChart(prices: [100, 130, 100])

        XCTAssertEqual(
            LimitChartReach.evaluate(chart: chart, target: 130, market: 100),
            .lastTraded(at: Date(timeIntervalSince1970: 60))
        )
    }

    func testReachWorksWithoutAMarketReference() {
        // No market yet ⇒ the below-market shortcut cannot apply, but the
        // history question still has an answer.
        let chart = makeChart(prices: [100, 130, 100])

        XCTAssertEqual(
            LimitChartReach.evaluate(chart: chart, target: 130, market: nil),
            .lastTraded(at: Date(timeIntervalSince1970: 60))
        )
    }
}
