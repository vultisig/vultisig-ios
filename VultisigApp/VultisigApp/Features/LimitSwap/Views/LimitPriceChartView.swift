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
/// `onTargetChanged`. It never rounds, clamps or stores the value: the form's
/// text field remains authoritative, and rounding a dragged price to something
/// sane is the view model's business. That split is what lets a typed target
/// sit far outside the plot without the chart quietly pulling it back in.
struct LimitPriceChartView: View {

    let chart: MarketChart
    /// THORChain's quote for the user's size. `nil` until the probe resolves —
    /// the plot then falls back to a data-anchored domain and draws no market
    /// rule, rather than holding the whole chart back.
    let market: Double?
    let target: Double
    let onTargetChanged: (Double) -> Void

    private var domain: ClosedRange<Double> {
        LimitChartDomain.range(for: chart, market: market)
    }

    /// Where the target line is *drawn*, which is not always where the target
    /// *is*: past the domain it pins to the edge and the value is spelled out
    /// instead. Rescaling the plot to chase it would squash the history away
    /// exactly when it is being read.
    private var drawnTarget: Double {
        min(max(target, domain.lowerBound), domain.upperBound)
    }

    private var isOffScale: Bool {
        LimitChartDomain.isOffScale(target: target, in: domain)
    }

    /// Warning state drives the target's colour, reusing the thresholds the
    /// form already validates against so the line and the warning row can never
    /// disagree.
    private var targetTint: Color {
        guard let market, market > 0 else { return Theme.colors.alertSuccess }
        if target <= market { return Theme.colors.alertError }
        if target > market * LimitChartDomain.farAboveMarketMultiple { return Theme.colors.alertWarning }
        return Theme.colors.alertSuccess
    }

    var body: some View {
        Chart {
            areaAndLine

            if let market, domain.contains(market) {
                marketRule(at: market)
            }

            guides

            band

            RuleMark(y: .value("target", drawnTarget))
                .foregroundStyle(targetTint)
                .lineStyle(
                    StrokeStyle(lineWidth: 1.5, dash: isOffScale ? [5, 4] : [])
                )
        }
        .chartXScale(domain: 0...Double(max(1, chart.points.count - 1)))
        .chartYScale(domain: domain)
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
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotOrigin = geometry[plotFrame].origin
                                guard let price = proxy.value(
                                    atY: value.location.y - plotOrigin.y,
                                    as: Double.self
                                ) else { return }
                                onTargetChanged(min(max(price, domain.lowerBound), domain.upperBound))
                            }
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel("limitSwap.chart.targetPrice".localized)
        .accessibilityValue(Text(String(format: "%.8f", target)))
        .accessibilityAdjustableAction { direction in
            guard let market, market > 0 else { return }
            let step = market * 0.005
            switch direction {
            case .increment: onTargetChanged(target + step)
            case .decrement: onTargetChanged(target - step)
            @unknown default: break
            }
        }
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
    private var areaAndLine: some ChartContent {
        ForEach(Array(chart.points.enumerated()), id: \.offset) { index, point in
            AreaMark(
                x: .value("position", Double(index)),
                yStart: .value("low", domain.lowerBound),
                yEnd: .value("price", point.price)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(areaGradient)

            LineMark(
                x: .value("position", Double(index)),
                y: .value("price", point.price)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(Theme.colors.primaryAccent3)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
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

    /// Ticks the drag zone at the preset pills' own stops. Left bare it reads as
    /// dead chart; ticked, the empty space above the series becomes the scale of
    /// distance-from-market that the feature is actually about.
    @ChartContentBuilder
    private var guides: some ChartContent {
        if let market, market > 0 {
            ForEach(LimitChartDomain.guidePercentages, id: \.self) { percentage in
                let level = market * (1 + Double(percentage) / 100)
                if domain.contains(level), abs(level - drawnTarget) > domain.span * 0.04 {
                    RuleMark(y: .value("guide", level))
                        .foregroundStyle(Theme.colors.textTertiary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 5]))
                }
            }
        }
    }

    /// The shaded band between market and target — the "range in comparison to
    /// the current price" this chart exists to show. The only filled region on
    /// the plot: shading the whole below-market half instead would tint most of
    /// the history red, and history sits below the current price about half the
    /// time.
    @ChartContentBuilder
    private var band: some ChartContent {
        if let market, market > 0 {
            RectangleMark(
                yStart: .value("from", min(market, drawnTarget)),
                yEnd: .value("to", max(market, drawnTarget))
            )
            .foregroundStyle(
                (target >= market ? Theme.colors.primaryAccent3 : Theme.colors.alertError)
                    .opacity(0.16)
            )
        }
    }
}

private extension ClosedRange where Bound == Double {
    var span: Double { upperBound - lowerBound }
}
