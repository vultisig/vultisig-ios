//
//  CoinPriceExtremesView.swift
//  VultisigApp
//
//  24h low–high band plus all-time high/low for the coin-detail sheet.
//

import SwiftUI

struct CoinPriceExtremesView: View {
    let stats: CoinMarketStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("priceRange".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            VStack(spacing: 0) {
                if stats.has24hRange {
                    dayRangeRow
                        .commonListItemContainer(index: 0, itemsCount: rowCount)
                }

                ForEach(Array(extremeRows.enumerated()), id: \.element.title) { index, row in
                    CoinMarketStatRow(title: row.title) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.value)
                                .font(Theme.fonts.priceBodyS)
                                .foregroundStyle(Theme.colors.textPrimary)

                            if let detail = row.detail {
                                Text(detail)
                                    .font(Theme.fonts.caption10)
                                    .foregroundStyle(Theme.colors.textTertiary)
                            }
                        }
                    }
                    .commonListItemContainer(
                        index: index + (stats.has24hRange ? 1 : 0),
                        itemsCount: rowCount
                    )
                }
            }
            .commonListContainer()
        }
    }

    private var rowCount: Int {
        extremeRows.count + (stats.has24hRange ? 1 : 0)
    }

    /// The 24h band with a marker showing where the price sits inside it —
    /// "near the day's high" is the thing this row exists to communicate, and a
    /// pair of numbers alone does not say it.
    @ViewBuilder
    private var dayRangeRow: some View {
        VStack(spacing: 8) {
            HStack {
                Text("low24h".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Text("high24h".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.colors.bgPrimary)
                        .frame(height: 4)

                    if let position = stats.positionIn24hRange {
                        Circle()
                            .fill(Theme.colors.primaryAccent4)
                            .frame(width: 8, height: 8)
                            .offset(x: (geometry.size.width - 8) * position)
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 8)

            HStack {
                Text(MarketStatFormatter.price(stats.low24h) ?? "")
                    .font(Theme.fonts.priceCaption)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                Text(MarketStatFormatter.price(stats.high24h) ?? "")
                    .font(Theme.fonts.priceCaption)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
        }
        .padding(16)
    }

    private var extremeRows: [(title: String, value: String, detail: String?)] {
        var entries: [(String, String, String?)] = []

        if let high = MarketStatFormatter.price(stats.ath) {
            entries.append((
                "allTimeHigh".localized,
                high,
                Self.detail(percentage: stats.athChangePercentage, date: stats.athDate)
            ))
        }
        if let low = MarketStatFormatter.price(stats.atl) {
            entries.append((
                "allTimeLow".localized,
                low,
                Self.detail(percentage: stats.atlChangePercentage, date: stats.atlDate)
            ))
        }

        return entries
    }

    /// "-49.31% · 6 Oct 2025" — the distance from the extreme and when it
    /// happened, which is what makes the bare number mean something.
    private static func detail(percentage: Double?, date: Date?) -> String? {
        let parts = [
            MarketStatFormatter.percentage(percentage),
            MarketStatFormatter.date(date)
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    let json = Data(#"""
    {"id":"bitcoin","current_price":63916,"high_24h":64008,"low_24h":62828,
     "ath":126080,"ath_change_percentage":-49.30513,"ath_date":"2025-10-06T18:57:42.558Z",
     "atl":67.81,"atl_change_percentage":94158.93421,"atl_date":"2013-07-06T00:00:00.000Z"}
    """#.utf8)

    return Group {
        if let stats = try? JSONDecoder().decode(CoinMarketStats.self, from: json) {
            CoinPriceExtremesView(stats: stats)
        }
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
