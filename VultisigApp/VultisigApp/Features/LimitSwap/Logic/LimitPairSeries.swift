//
//  LimitPairSeries.swift
//  VultisigApp
//
//  Builds the price history a limit order actually triggers on: the ratio
//  between the two assets, derived from their two fiat series.
//

import Foundation

/// Derives a pair-ratio series — "how many of the target asset one source asset
/// buys" — from the two per-coin fiat series the market-data service returns.
///
/// The limit form's canonical `targetPrice` is that ratio, and it is what the
/// memo's `LIM` is computed from. A fiat series for the source asset alone is a
/// different quantity: it only coincides with the trigger when the target side
/// is a stablecoin, and drifts away from it as soon as the target asset moves.
/// Drawing a target line over the fiat series would therefore put the line at a
/// level the order does not actually fire at, so the chart is fed from here.
///
/// The fiat unit cancels in the division, which is why the result needs no
/// currency of its own and does not have to be refetched when
/// `SettingsCurrency` changes — unlike the per-coin series it is built from.
enum LimitPairSeries {

    /// The ratio series for `base / quote`, or `nil` when one cannot honestly be
    /// drawn.
    ///
    /// Both inputs are sampled onto **one shared grid laid across the interval
    /// they overlap in**, rather than each being resampled independently and
    /// divided position-by-position. Two series requested for the same `days`
    /// still open and close at their own instants — each coin's samples are
    /// stamped when that coin was observed — so independent grids put position
    /// `i` at a different moment in each series, and the quotient at that
    /// position would divide two prices from times minutes or hours apart. Over
    /// a long window that is invisible; across a sharp move in one asset it
    /// invents a spike in the ratio that neither asset had.
    ///
    /// Returns `nil` when either source is too sparse to draw (the shared
    /// `isUsable` floor — interpolating 200 samples out of three observations
    /// would manufacture a confident-looking line from almost no data), when
    /// the two windows do not overlap, or when either side carries a sample
    /// that is not a positive finite price.
    ///
    /// That last check is on the **source samples**, not on the interpolated
    /// divisor, and the difference is not academic. A single zero in the quote
    /// series is almost never landed on exactly by the output grid; the
    /// interpolation instead smears it across its neighbours as a run of
    /// near-zero divisors, and the ratio comes out as a spike of arbitrary
    /// height — 40× the true value on a 200-point grid, in the case that found
    /// this — rather than as anything a guard on the quotient would catch. So
    /// the series is rejected before any interpolation happens.
    static func ratio(
        base: MarketChart,
        quote: MarketChart,
        count: Int = MarketChartRendering.pointCount
    ) -> MarketChart? {
        guard count > 1, base.isUsable, quote.isUsable else { return nil }
        guard isPositivelyPriced(base), isPositivelyPriced(quote) else { return nil }
        guard let baseFirst = base.points.first, let baseLast = base.points.last,
              let quoteFirst = quote.points.first, let quoteLast = quote.points.last
        else { return nil }

        let start = max(baseFirst.date, quoteFirst.date)
        let end = min(baseLast.date, quoteLast.date)
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return nil }

        var baseSampler = Sampler(points: base.points)
        var quoteSampler = Sampler(points: quote.points)

        var samples: [MarketChartPoint] = []
        samples.reserveCapacity(count)

        for position in 0..<count {
            let instant = start.addingTimeInterval(span * Double(position) / Double(count - 1))
            // No divide-by-zero check here, and none is needed: every source
            // sample is positive by the guard above, and a linear interpolation
            // between two positive endpoints is positive.
            samples.append(
                MarketChartPoint(
                    date: instant,
                    price: baseSampler.price(at: instant) / quoteSampler.price(at: instant)
                )
            )
        }

        return MarketChart(points: samples)
    }

    /// Whether every sample in the series is a price that can take part in a
    /// ratio. Zero and negative prices have no meaningful reciprocal, and a
    /// non-finite one poisons every sample downstream of it.
    private static func isPositivelyPriced(_ chart: MarketChart) -> Bool {
        chart.points.allSatisfy { $0.price > 0 && $0.price.isFinite }
    }

    /// Reads a price out of an ascending series at an arbitrary instant,
    /// interpolating between the two observations that bracket it.
    ///
    /// Holds a cursor rather than searching per call: the grid it is queried
    /// with ascends and so do the points, so the whole series is walked once
    /// across a full pass instead of binary-searched `count` times.
    private struct Sampler {

        private let points: [MarketChartPoint]
        private var cursor = 0

        init(points: [MarketChartPoint]) {
            self.points = points
        }

        mutating func price(at instant: Date) -> Double {
            guard let first = points.first, let last = points.last else { return 0 }
            // The grid is built from the overlap, so neither clamp fires in
            // production. They are what makes the type safe to reuse against a
            // grid derived some other way, rather than silently reading the
            // wrong end of the series.
            if instant <= first.date { return first.price }
            if instant >= last.date { return last.price }

            while cursor + 2 < points.count, points[cursor + 1].date <= instant {
                cursor += 1
            }

            let start = points[cursor]
            let end = points[cursor + 1]
            let interval = end.date.timeIntervalSince(start.date)
            guard interval > 0 else { return start.price }

            let fraction = instant.timeIntervalSince(start.date) / interval
            return start.price + (end.price - start.price) * fraction
        }
    }
}
