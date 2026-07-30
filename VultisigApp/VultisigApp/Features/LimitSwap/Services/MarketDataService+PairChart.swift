//
//  MarketDataService+PairChart.swift
//  VultisigApp
//
//  Composes two per-coin fiat series into the pair-ratio series the limit
//  chart plots.
//

import Foundation

extension MarketDataServiceProtocol {

    /// Price history for `base` measured in `quote` — the quantity the limit
    /// form's target price is expressed in.
    ///
    /// Deliberately built on top of `chart(for:range:currency:)` rather than
    /// beside it, so the pair series inherits everything that path already
    /// does: the per-source TTL cache, its in-flight coalescing (a double-tap
    /// on a range does not fetch twice), the fail-open to the last good
    /// snapshot, and the sparse-series floor. The two legs are fetched
    /// concurrently because neither depends on the other.
    ///
    /// `currency` cancels out of the division, so it does not affect the
    /// result — it is threaded through anyway so both legs read from the SAME
    /// cache entries the rest of the app already populated for the user's
    /// currency. Pinning it to USD instead would be correct arithmetic and a
    /// second, redundant network fetch for everyone not on USD.
    ///
    /// `nil` when either side has no CoinGecko source, when either fetch fails
    /// with nothing cached, or when the two histories cannot be reconciled
    /// (`LimitPairSeries.ratio`). Every one of those degrades to the limit form
    /// as it was before the chart — never to a blocked order.
    func pairChart(
        base: CoinMeta,
        quote: CoinMeta,
        range: MarketChartRange,
        currency: SettingsCurrency
    ) async -> MarketChart? {
        async let baseSeries = chart(for: base, range: range, currency: currency)
        async let quoteSeries = chart(for: quote, range: range, currency: currency)

        guard let baseSeries = await baseSeries, let quoteSeries = await quoteSeries else {
            return nil
        }
        return LimitPairSeries.ratio(base: baseSeries, quote: quoteSeries)
    }
}
