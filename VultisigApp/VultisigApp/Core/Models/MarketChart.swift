//
//  MarketChart.swift
//  VultisigApp
//
//  Price-history models for the coin-detail chart, decoded from the CoinGecko
//  proxy's `market_chart` response.
//

import Foundation

/// One sample of a price series: a timestamp and the price in the requested fiat.
struct MarketChartPoint: Hashable, Sendable {
    let date: Date
    let price: Double
}

/// A decoded price series for one coin over one range.
///
/// Only `prices` is read out of the payload. `market_caps` and `total_volumes`
/// arrive in the same response but nothing renders them — market cap and volume
/// come from the richer `/coins/markets` record instead — and skipping them
/// avoids parsing two extra arrays that are ~4.8k samples each on `days=max`.
///
/// `Hashable` so the chart view can adopt the series itself as its view
/// identity: a new window then *replaces* the plot instead of morphing the
/// marks of the previous one into it.
struct MarketChart: Hashable, Sendable {

    /// Fewest samples a series needs before it is worth drawing.
    ///
    /// Below this a "chart" is a two- or three-point polyline: a straight
    /// segment that reads as a confident trend while actually being an artifact
    /// of having almost no history. Thinly traded and freshly listed tokens are
    /// where this happens — a token listed yesterday returns a handful of daily
    /// samples for `1Y`/`ALL`, and one that has never traded in the window can
    /// return an empty array. Those render with the chart hidden rather than
    /// with a misleading line.
    ///
    /// A *flat* series is deliberately not covered by this: a pegged stablecoin
    /// whose price genuinely did not move has hundreds of samples and a
    /// horizontal line is the honest picture, so it draws (see `priceDomain`,
    /// which keeps that line off the plot's floor).
    static let minimumUsablePoints = 10

    /// Samples in ascending timestamp order.
    let points: [MarketChartPoint]

    init(points: [MarketChartPoint]) {
        self.points = points
    }

    /// Whether the series has enough history to draw honestly.
    var isUsable: Bool {
        points.count >= Self.minimumUsablePoints
    }

    var firstPrice: Double? { points.first?.price }
    var lastPrice: Double? { points.last?.price }

    /// Change over the whole window, as a fraction (`0.05` = +5%). `nil` when
    /// the series is empty or opens at zero, where a percentage is undefined.
    var changeFraction: Double? {
        guard let first = firstPrice, let last = lastPrice, first != 0 else { return nil }
        return (last - first) / abs(first)
    }

    /// Fraction of the window's span left free above and below the line.
    ///
    /// With a domain of exactly `min...max` the highest and lowest samples land
    /// on the plot's edges and the stroke is clipped down the middle, which
    /// reads as the chart being cut off.
    static let domainHeadroom = 0.08

    /// Closed y-domain for the plot.
    ///
    /// A perfectly flat series has `min == max`, which Charts renders as a
    /// degenerate domain — the line lands on the axis instead of through the
    /// plot. Padding it keeps a flat line centred and visible.
    var priceDomain: ClosedRange<Double> {
        let prices = points.map(\.price)
        guard let lowest = prices.min(), let highest = prices.max() else {
            return 0...1
        }
        let span = highest - lowest
        guard span > 0 else {
            let padding = abs(lowest) * 0.05
            let inset = padding > 0 ? padding : 1
            return (lowest - inset)...(highest + inset)
        }
        let inset = span * Self.domainHeadroom
        return (lowest - inset)...(highest + inset)
    }

    /// Resamples the series onto exactly `count` samples spread evenly across
    /// the window's *elapsed time*.
    ///
    /// A resample, not a cap: a window with fewer samples than `count` is
    /// interpolated *up* rather than passed through. Every range therefore
    /// reaches the chart with the same number of marks, which is what lets one
    /// window morph into the next — Charts identifies marks by array position,
    /// so index `i` has to mean the same relative position in both series. When
    /// the counts differ instead, the surplus marks are removed mid-switch and
    /// fade out at their old coordinates, on top of the incoming line.
    ///
    /// The grid is laid out in time rather than over the source array, so index
    /// `i` means the same fraction of the *window* and not merely the same
    /// fraction of however many samples came back. The upstream series is
    /// nominally regular but not guaranteed to be — a null sample is dropped
    /// during decoding, and a quiet token can simply be missing hours — and a
    /// plot whose x is the sample's index would otherwise give a six-hour gap
    /// the same width as the five minutes either side of it, moving the price
    /// action to a time it did not happen at.
    ///
    /// The first and last samples are carried over untouched, so the window's
    /// opening and closing prices — and the change percentage read off them —
    /// survive the resample exactly. Interior samples are the price linearly
    /// interpolated between the two observations their instant falls between.
    ///
    /// A series of fewer than two samples, a `count` below two, or a window of
    /// zero elapsed time has no grid to lay out and comes back unchanged rather
    /// than padded out: a series that degenerate has already failed `isUsable`
    /// and is not going to be drawn.
    ///
    /// Relies on `points` being in ascending timestamp order, which is the
    /// type's invariant and is established where the series is decoded. It is
    /// not re-checked here: sorting on every call would cost the long windows a
    /// pass over thousands of samples to rule out a state the only production
    /// construction site cannot produce.
    func resampled(to count: Int = MarketChartRendering.pointCount) -> MarketChart {
        guard count > 1, points.count > 1 else { return self }

        let opening = points[0]
        let closing = points[points.count - 1]
        let span = closing.date.timeIntervalSince(opening.date)
        guard span > 0 else { return self }

        var samples: [MarketChartPoint] = [opening]
        samples.reserveCapacity(count)

        // The source samples bracketing the instant being solved for. Both the
        // grid and the series ascend, so this only ever walks forwards.
        var cursor = 0

        for position in 1..<(count - 1) {
            let instant = opening.date.addingTimeInterval(
                span * Double(position) / Double(count - 1)
            )
            while cursor + 2 < points.count, points[cursor + 1].date <= instant {
                cursor += 1
            }

            let start = points[cursor]
            let end = points[cursor + 1]
            let interval = end.date.timeIntervalSince(start.date)
            let fraction = interval > 0 ? instant.timeIntervalSince(start.date) / interval : 0

            samples.append(
                MarketChartPoint(
                    date: instant,
                    price: start.price + (end.price - start.price) * fraction
                )
            )
        }

        samples.append(closing)
        return MarketChart(points: samples)
    }
}

enum MarketChartRendering {
    /// Samples every series is resampled to before it reaches Charts.
    ///
    /// Roughly one sample per two points of plot width on the widest phone —
    /// finer than the 2pt stroke can express, so no visible detail is lost —
    /// and it is now a floor as well as a ceiling: every mark animates on every
    /// range switch, so the count is what one morph costs.
    static let pointCount = 200
}

// MARK: - Decoding

extension MarketChart: Decodable {

    private enum CodingKeys: String, CodingKey {
        case prices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decoded as optional doubles so a `null` sample — the one malformation
        // the upstream payload actually produces — drops that pair instead of
        // failing the whole series.
        let rawPairs = try container.decode([[Double?]].self, forKey: .prices)
        self.init(points: MarketChart.points(from: rawPairs))
    }

    /// Maps CoinGecko's `[[msEpoch, price]]` array-of-arrays into samples.
    ///
    /// Pairs that are short, empty, null-valued or non-finite are dropped
    /// rather than failing the whole decode — one bad sample should not cost
    /// the user the chart. The result is sorted because nothing in the response
    /// contract guarantees ascending timestamps, and Charts draws a line in
    /// the order it is given.
    ///
    /// Samples that repeat a timestamp are collapsed to the last one. Two
    /// points at the same instant are not something a price line can express,
    /// and a zero-length interval has no meaningful price to interpolate across
    /// when the series is resampled onto a time grid.
    static func points(from rawPairs: [[Double?]]) -> [MarketChartPoint] {
        let parsed = rawPairs
            .compactMap { pair -> MarketChartPoint? in
                guard pair.count >= 2,
                      let milliseconds = pair[0],
                      let price = pair[1],
                      milliseconds.isFinite,
                      price.isFinite else {
                    return nil
                }
                return MarketChartPoint(
                    date: Date(timeIntervalSince1970: milliseconds / 1000),
                    price: price
                )
            }
            .sorted { $0.date < $1.date }

        return parsed.reduce(into: [MarketChartPoint]()) { result, point in
            if result.last?.date == point.date {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
    }
}

// MARK: - Range

/// The selectable chart windows.
enum MarketChartRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year
    case all

    var id: String { rawValue }

    /// CoinGecko's `days` query value.
    ///
    /// Granularity is implied by it on the free tier (`<= 1` → 5-minutely,
    /// `2...90` → hourly, `> 90` → daily); the explicit `interval` parameter is
    /// a paid feature. That is why sample counts differ by an order of
    /// magnitude between ranges and every series goes through `resampled`.
    var days: String {
        switch self {
        case .day: return "1"
        case .week: return "7"
        case .month: return "30"
        case .year: return "365"
        case .all: return "max"
        }
    }

    var title: String {
        switch self {
        case .day: return "chartRangeDay".localized
        case .week: return "chartRangeWeek".localized
        case .month: return "chartRangeMonth".localized
        case .year: return "chartRangeYear".localized
        case .all: return "chartRangeAll".localized
        }
    }

    /// How long a fetched series stays fresh. Short windows move continuously;
    /// the long ones are daily samples that only gain a point once a day.
    var cacheTTL: TimeInterval {
        switch self {
        case .day: return 60
        case .week, .month: return 600
        case .year, .all: return 3600
        }
    }

    /// Label for the scrubbed sample. A one-day window needs the clock time; a
    /// multi-year one needs the year, and showing both everywhere would make
    /// the floating label jump between widths as the range changes.
    func formattedScrubDate(_ date: Date) -> String {
        switch self {
        case .day:
            return date.formatted(date: .omitted, time: .shortened)
        case .week, .month:
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        case .year, .all:
            return date.formatted(.dateTime.year().month(.abbreviated).day())
        }
    }
}
