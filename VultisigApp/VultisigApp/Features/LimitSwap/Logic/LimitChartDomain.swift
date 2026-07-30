//
//  LimitChartDomain.swift
//  VultisigApp
//
//  The y-domain the limit chart plots into, and whether the target has left it.
//

import Foundation

/// The vertical range the limit form's price chart plots into.
///
/// Deliberately **not** `MarketChart.priceDomain`, which the coin-detail chart
/// uses. That one is anchored to the data: it spans the series and nothing else,
/// because there a chart is only ever a picture of what happened. Here the plot
/// is also an input — the region above the series is where the target gets
/// dragged — so a domain derived from the series alone leaves nowhere to drag
/// to, and one widened to swallow the target moves under the user's finger as
/// they drag, squashing the history in real time exactly when they are reading
/// it.
///
/// So the domain is anchored to the **market price** and is independent of the
/// target. It is fixed for as long as the market reference and the series are,
/// which is what makes dragging feel like moving a line over a chart rather than
/// like zooming one.
enum LimitChartDomain {

    /// How far below market the plot reaches before the series pushes it down.
    ///
    /// Small: below-market targets are the immediate-fill case the form already
    /// warns about, so the space is worth little, and the series usually spends
    /// time down here anyway and widens it for free.
    static let floorFraction = 0.97

    /// How far above market the plot reaches before the series pushes it up.
    ///
    /// This is the **preset pills' reach** (`+10%`, plus room to see it), not
    /// the `1.2×` "far above market" warning threshold. Pinning the ceiling to
    /// the warning instead spends a quarter of the plot on empty space every
    /// time the pair is calm — the history compresses into a squiggle along the
    /// bottom, and the chart is least readable exactly when it is being used.
    /// Targets past this are legal and reachable by typing; they render as the
    /// off-scale state rather than by rescaling the plot.
    static let ceilingFraction = 1.12

    /// Fraction of the span left free at each end so the line and the market
    /// rule are not drawn along the plot's edges.
    static let headroom = 0.06

    /// The domain for `chart` given `market`, or the chart's own data-anchored
    /// domain when there is no market reference yet (the quote probe is async,
    /// so the first frames can arrive without one).
    static func range(for chart: MarketChart, market: Double?) -> ClosedRange<Double> {
        guard let market, market > 0, market.isFinite else { return chart.priceDomain }

        // A non-finite sample would make `span` infinite and the domain
        // `-infinity ... +infinity`, which collapses the whole plot rather than
        // just that point. Series reaching here are already validated, so this
        // only bounds the damage if a future producer is not.
        let prices = chart.points.map(\.price).filter(\.isFinite)
        let low = min(prices.min() ?? market, market * floorFraction)
        let high = max(prices.max() ?? market, market * ceilingFraction)

        let span = high - low
        guard span > 0 else {
            let inset = abs(market) * 0.05
            return (low - inset)...(high + inset)
        }
        let inset = span * headroom
        return (low - inset)...(high + inset)
    }

    /// Whether `target` sits outside `domain` and must be drawn pinned to an
    /// edge instead of in place.
    ///
    /// The value is never clamped to fit — the text field stays authoritative,
    /// and a target the user typed is shown as typed. Only its *position* is
    /// pinned.
    static func isOffScale(target: Double, in domain: ClosedRange<Double>) -> Bool {
        !domain.contains(target)
    }

    /// The multiples of the market price to tick the drag zone at.
    ///
    /// They are the preset pills' own stops, so the empty region above the
    /// series reads as a scale of distance-from-market rather than as dead
    /// chart — which is the thing the feature was asked for.
    static let guidePercentages = [5, 10]
}
