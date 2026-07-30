//
//  LimitChartReach.swift
//  VultisigApp
//
//  Whether the pair has ever traded at the target price inside the window on
//  screen — the question a limit-price chart exists to answer.
//

import Foundation

/// Answers "has this pair been here before?" for the target price, against the
/// window currently plotted.
///
/// A target above everything in the window is the normal case for a limit sell,
/// not an error — so the useful thing to say is not "invalid" but *how far out*
/// it is: the last time the pair traded there, or that it never has inside this
/// range. That is what makes the expiry pills legible; a target the pair last
/// touched three months ago, with a 12h expiry, is visibly a bad bet.
///
/// Returns a `Date` rather than formatted text so the phrasing and the
/// localization stay in the view, and the verdict itself stays testable.
enum LimitChartReach {

    enum Verdict: Equatable {
        /// The target is at or below market: it fills as soon as it rests.
        /// Matches the form's existing `priceAtOrBelowMarket` warning boundary.
        case atOrBelowMarket
        /// The pair last traded at or above the target at this instant.
        case lastTraded(at: Date)
        /// The window never reached the target; `highest` is the best it did.
        case notReached(highest: Double)
    }

    static func evaluate(chart: MarketChart, target: Double, market: Double?) -> Verdict {
        if let market, market > 0, target <= market {
            return .atOrBelowMarket
        }

        // Walk back from the most recent sample: the answer wanted is the LAST
        // time the price was here, not the first.
        if let touched = chart.points.last(where: { $0.price >= target }) {
            return .lastTraded(at: touched.date)
        }

        return .notReached(highest: chart.points.map(\.price).max() ?? 0)
    }
}
