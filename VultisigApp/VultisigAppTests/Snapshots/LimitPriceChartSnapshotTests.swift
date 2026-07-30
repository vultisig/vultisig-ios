//
//  LimitPriceChartSnapshotTests.swift
//  VultisigAppTests
//
//  Renders the limit chart's states. A chart is one of the few things where
//  passing tests say almost nothing — the domain policy, the pinned off-scale
//  label and the guide placement are all judgements about pixels.
//

import SnapshotTesting
import SwiftUI
import XCTest

@testable import VultisigApp

@MainActor
final class LimitPriceChartSnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        // Set to true to generate/update reference images, then back to false
        // isRecording = true
    }

    /// A deterministic month of a pair drifting upward, with the shape of a real
    /// series rather than a smooth curve. Seeded so the reference images do not
    /// move between runs.
    private func series(count: Int = 200, end: Double = 30.42) -> MarketChart {
        var state: UInt64 = 42
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 33) / Double(UInt64(1) << 31) - 0.5
        }
        var prices = [Double](repeating: end, count: count)
        for index in stride(from: count - 2, through: 0, by: -1) {
            prices[index] = prices[index + 1] / (1 + next() * 0.012 + 0.0012)
        }
        let start = Date(timeIntervalSince1970: 1_753_000_000)
        return MarketChart(points: prices.enumerated().map { index, price in
            MarketChartPoint(
                date: start.addingTimeInterval(Double(index) * 12_960),
                price: price
            )
        })
    }

    private func chart(target: Double, market: Double? = 30.31, label: String) -> some View {
        LimitPriceChartView(
            chart: series(),
            market: market,
            target: target,
            targetLabel: label,
            onTargetChanged: { _ in }
        )
        .frame(width: 344, height: 148)
        .padding(16)
        .background(Theme.colors.bgPrimary)
        .colorScheme(.dark)
    }

    private func assertChart(_ view: some View, _ name: String, line: UInt = #line) {
        assertSnapshot(
            of: view,
            as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .fixed(width: 376, height: 180)),
            named: name,
            line: line
        )
    }

    func testTargetAboveMarketWithinTheDragZone() {
        assertChart(chart(target: 31.83, label: "31.83 ETH"), "above-market")
    }

    func testTargetAtTheTopOfTheDragZone() {
        assertChart(chart(target: 33.5, label: "33.5 ETH"), "near-ceiling")
    }

    func testTargetOffScalePinsAndLabels() {
        // The state the plot cannot express by position alone — the number has
        // to be legible on the chart itself.
        assertChart(chart(target: 37.0, label: "37 ETH"), "off-scale")
    }

    func testTargetBelowMarketShowsTheFillNowBand() {
        assertChart(chart(target: 29.1, label: "29.1 ETH"), "below-market")
    }

    func testWithoutAMarketReferenceYet() {
        // The quote probe is async; the first frames legitimately have no market.
        assertChart(chart(target: 31.83, market: nil, label: "31.83 ETH"), "no-market")
    }
}
