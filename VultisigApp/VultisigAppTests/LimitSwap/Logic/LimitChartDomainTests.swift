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

    func testDomainDoesNotDependOnTheTarget() {
        // The property that makes dragging stable: nothing about the target
        // enters the calculation, so the plot cannot move under the finger.
        let first = LimitChartDomain.range(for: calmChart, market: 100)
        let second = LimitChartDomain.range(for: calmChart, market: 100)

        XCTAssertEqual(first, second)
        XCTAssertTrue(LimitChartDomain.isOffScale(target: 400, in: first))
        XCTAssertEqual(LimitChartDomain.range(for: calmChart, market: 100), first)
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

    // MARK: - Reach

    func testReachReportsAtOrBelowMarketOnTheBoundary() {
        let chart = calmChart

        XCTAssertEqual(LimitChartReach.evaluate(chart: chart, target: 100, market: 100), .atOrBelowMarket)
        XCTAssertEqual(LimitChartReach.evaluate(chart: chart, target: 90, market: 100), .atOrBelowMarket)
    }

    func testReachReportsTheMostRecentTouchNotTheFirst() {
        // Price hits 120 early and again late; the useful answer is the late one.
        let chart = makeChart(prices: [100, 120, 100, 100, 120, 100, 100])
        let verdict = LimitChartReach.evaluate(chart: chart, target: 115, market: 100)

        XCTAssertEqual(verdict, .lastTraded(at: Date(timeIntervalSince1970: 240)))
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
