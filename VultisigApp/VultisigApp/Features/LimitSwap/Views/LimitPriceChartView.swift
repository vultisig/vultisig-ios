//
//  LimitPriceChartView.swift
//  VultisigApp
//
//  The limit form's price chart: the pair's recent history with the target
//  price as a line you drag.
//

import Charts
import SwiftUI

/// Plots the pair-ratio history and the target price over it, and lets the
/// target be dragged.
///
/// Presentational only — it renders `target` and reports drags through
/// `onTargetChanged`. It never rounds or stores the value: the form's text
/// field remains authoritative, and rounding a dragged price to something sane
/// is the view model's business. That split is what lets a typed target sit far
/// outside the plot without the chart quietly pulling it back in.
struct LimitPriceChartView: View {

    let chart: MarketChart
    /// THORChain's quote for the user's size. `nil` until the probe resolves —
    /// the plot then falls back to a data-anchored domain and draws no market
    /// rule, rather than holding the whole chart back.
    let market: Double?
    let target: Double
    /// The target formatted for display, supplied by the caller because how a
    /// price is written is the form's decision, not the plot's. Shown only when
    /// the target is off-scale, where the line's position no longer tells the
    /// user what their order is.
    let targetLabel: String
    let onTargetChanged: (Double) -> Void

    var body: some View {
        // Everything derived is computed ONCE here and handed to the mark
        // builders. `domain` in particular walks the whole series; read as a
        // computed property from inside the per-point `ForEach` it was
        // recomputed for all 200 points, on every frame of a drag.
        let layout = Layout(chart: chart, market: market, target: target)

        Chart {
            areaAndLine(layout)

            if let market = layout.market {
                marketRule(at: market)
            }

            guides(layout)
            band(layout)

            if let drawn = layout.drawnTarget {
                targetRule(at: drawn, layout: layout)
            }
        }
        .chartXScale(domain: 0...Double(max(1, layout.points.count - 1)))
        .chartYScale(domain: layout.domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    // A drag, not `chartXSelection`: that reads a series along x,
                    // and this moves a value along y. It is also the same gesture
                    // on both platforms — click-and-drag is how a Mac moves a
                    // handle — so unlike the coin-detail scrub there is no
                    // hover-vs-touch split to make here.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                report(gestureAt: value.location, proxy: proxy, geometry: geometry, layout: layout)
                            }
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel("limitSwap.chart.targetPrice".localized)
        .accessibilityValue(targetLabel)
        .accessibilityAdjustableAction { direction in
            // Routed through the same clamp the drag uses. Nudging must not be
            // able to produce a value a drag could not — without this, repeated
            // decrements walk the target below zero.
            guard let market = layout.market else { return }
            let step = market * Self.accessibilityStepFraction
            switch direction {
            case .increment: report(price: target + step, layout: layout)
            case .decrement: report(price: target - step, layout: layout)
            @unknown default: break
            }
        }
    }

    /// One nudge of the accessibility adjustable action, as a share of market.
    private static let accessibilityStepFraction = 0.005

    // MARK: - Reporting

    private func report(gestureAt location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, layout: Layout) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plot = geometry[plotFrame]
        // The overlay covers the whole chart, including the insets outside the
        // plot. Without this a press starting in an inset resolves to a price
        // that was never under the finger and then clamps to a domain edge,
        // which reads as the line jumping to a value the user did not choose.
        guard plot.contains(location) else { return }
        guard let price = proxy.value(atY: location.y - plot.origin.y, as: Double.self) else { return }
        report(price: price, layout: layout)
    }

    /// The single seam every reported price passes through, so the drag and the
    /// accessibility action cannot diverge on what is a legal value.
    private func report(price: Double, layout: Layout) {
        guard price.isFinite else { return }
        onTargetChanged(min(max(price, layout.domain.lowerBound), layout.domain.upperBound))
    }

    // MARK: - Marks

    /// Hoisted out of the mark builder deliberately: inline, the gradient makes
    /// the `ForEach` body too much for the type checker to solve in reasonable
    /// time.
    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [
                Theme.colors.primaryAccent3.opacity(0.38),
                Theme.colors.primaryAccent3.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ChartContentBuilder
    private func areaAndLine(_ layout: Layout) -> some ChartContent {
        // Both of these are hoisted out of the loop body for the type checker,
        // which will not solve the `ForEach` closure in reasonable time when it
        // has to resolve a member chain and a gradient per mark. They are also
        // loop invariants, so the hoist is free.
        let floor = layout.domain.lowerBound
        let accent = Theme.colors.primaryAccent3
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        ForEach(Array(layout.points.enumerated()), id: \.offset) { index, point in
            AreaMark(
                x: .value("position", Double(index)),
                yStart: .value("low", floor),
                yEnd: .value("price", point.price)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(areaGradient)

            LineMark(
                x: .value("position", Double(index)),
                y: .value("price", point.price)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(accent)
            .lineStyle(stroke)
        }
    }

    private func marketRule(at market: Double) -> some ChartContent {
        RuleMark(y: .value("market", market))
            .foregroundStyle(Theme.colors.textTertiary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text("limitSwap.chart.market".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
    }

    private func targetRule(at drawn: Double, layout: Layout) -> some ChartContent {
        RuleMark(y: .value("target", drawn))
            .foregroundStyle(layout.targetTint)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: layout.isOffScale ? [5, 4] : []))
            .annotation(
                position: layout.isPinnedToTop ? .bottom : .top,
                alignment: .trailing,
                spacing: 2
            ) {
                // Off the scale the line's position stops telling the user what
                // their order is — it only says "past here". The number has to
                // be on the plot, or the chart shows a price that is not the one
                // being placed.
                if layout.isOffScale {
                    Text(verbatim: "\(layout.isPinnedToTop ? "▲" : "▼") \(targetLabel)")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(layout.targetTint)
                }
            }
    }

    /// Ticks the drag zone at the preset pills' own stops. Left bare it reads as
    /// dead chart; ticked, the empty space above the series becomes the scale of
    /// distance-from-market that the feature is actually about.
    @ChartContentBuilder
    private func guides(_ layout: Layout) -> some ChartContent {
        ForEach(layout.guideLevels, id: \.self) { level in
            RuleMark(y: .value("guide", level))
                .foregroundStyle(Theme.colors.textTertiary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 5]))
        }
    }

    /// The shaded band between market and target — the "range in comparison to
    /// the current price" this chart exists to show. The only filled region on
    /// the plot: shading the whole below-market half instead would tint most of
    /// the history red, and history sits below the current price about half the
    /// time.
    @ChartContentBuilder
    private func band(_ layout: Layout) -> some ChartContent {
        if let bounds = layout.bandBounds {
            RectangleMark(
                yStart: .value("from", bounds.lowerBound),
                yEnd: .value("to", bounds.upperBound)
            )
            .foregroundStyle(layout.bandTint.opacity(0.16))
        }
    }
}

// MARK: - Derived geometry

extension LimitPriceChartView {

    /// Everything the marks need, resolved once per body evaluation.
    ///
    /// It is also the single place non-finite values are screened out. The
    /// series reaching this view is validated upstream, but Charts is not
    /// forgiving of an infinity in a mark, and a NaN survives `min`/`max`
    /// unchanged — so clamping alone does not sanitise a target.
    struct Layout {

        let points: [MarketChartPoint]
        let domain: ClosedRange<Double>
        let market: Double?
        /// `nil` when the target is not a drawable number, which suppresses the
        /// target rule and the band rather than feeding NaN into Charts.
        let drawnTarget: Double?
        let isOffScale: Bool
        let isPinnedToTop: Bool
        let targetTint: Color
        let bandBounds: ClosedRange<Double>?
        let bandTint: Color

        init(chart: MarketChart, market rawMarket: Double?, target: Double) {
            let sanitised = MarketChart(points: chart.points.filter(\.price.isFinite))
            points = sanitised.points

            let market = rawMarket.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            self.market = market
            domain = LimitChartDomain.range(for: sanitised, market: market)

            if target.isFinite {
                let drawn = min(max(target, domain.lowerBound), domain.upperBound)
                drawnTarget = drawn
                isOffScale = LimitChartDomain.isOffScale(target: target, in: domain)
                isPinnedToTop = target > domain.upperBound
                if let market {
                    bandBounds = min(market, drawn)...max(market, drawn)
                    bandTint = target >= market ? Theme.colors.primaryAccent3 : Theme.colors.alertError
                } else {
                    bandBounds = nil
                    bandTint = .clear
                }
                if let market {
                    if target <= market {
                        targetTint = Theme.colors.alertError
                    } else if target > market * LimitChartDomain.farAboveMarketMultiple {
                        targetTint = Theme.colors.alertWarning
                    } else {
                        targetTint = Theme.colors.alertSuccess
                    }
                } else {
                    targetTint = Theme.colors.alertSuccess
                }
            } else {
                drawnTarget = nil
                isOffScale = false
                isPinnedToTop = false
                targetTint = Theme.colors.alertSuccess
                bandBounds = nil
                bandTint = .clear
            }
        }

        /// Guide levels that are inside the plot and far enough from the target
        /// line not to draw on top of it.
        var guideLevels: [Double] {
            guard let market else { return [] }
            let separation = (domain.upperBound - domain.lowerBound) * 0.04
            return LimitChartDomain.guidePercentages.compactMap { percentage in
                let level = market * (1 + Double(percentage) / 100)
                guard domain.contains(level) else { return nil }
                if let drawnTarget, abs(level - drawnTarget) <= separation { return nil }
                return level
            }
        }
    }
}
