//
//  CoinMarketStatsView.swift
//  VultisigApp
//
//  Market cap / rank / FDV / volume / supply for the coin-detail sheet.
//

import SwiftUI

struct CoinMarketStatsView: View {
    let stats: CoinMarketStats
    let ticker: String

    /// Whether the card has anything to say. A `/markets` record can come back
    /// with an id and nothing else, and a titled card with no rows is worse
    /// than no card.
    var hasContent: Bool { !rows.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("marketStats".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.title) { index, row in
                    CoinMarketStatRow(title: row.title, value: row.value)
                        .commonListItemContainer(index: index, itemsCount: rows.count)
                }
            }
            .commonListContainer()
        }
    }

    /// Only the rows CoinGecko actually answered. An asset with no cap, no
    /// max supply or no FDV simply has a shorter card — the alternative is
    /// several rows of placeholder dashes.
    private var rows: [(title: String, value: String)] {
        var entries: [(String, String)] = []

        if let marketCap = MarketStatFormatter.fiat(stats.marketCap) {
            entries.append(("marketCap".localized, marketCap))
        }
        if let rank = stats.marketCapRank {
            entries.append(("marketCapRank".localized, "#\(rank)"))
        }
        if let volume = MarketStatFormatter.fiat(stats.totalVolume) {
            entries.append(("volume24h".localized, volume))
        }
        if let valuation = MarketStatFormatter.fiat(stats.fullyDilutedValuation) {
            entries.append(("fullyDilutedValuation".localized, valuation))
        }
        if let circulating = MarketStatFormatter.supply(stats.circulatingSupply, ticker: ticker) {
            entries.append(("circulatingSupply".localized, circulating))
        }
        if let maxSupply = MarketStatFormatter.supply(stats.maxSupply, ticker: ticker) {
            entries.append(("maxSupply".localized, maxSupply))
        }

        return entries
    }
}

#Preview {
    let json = Data(#"""
    {"id":"bitcoin","current_price":63916,"market_cap":1282270987961,"market_cap_rank":1,
     "fully_diluted_valuation":1282270987961,"total_volume":24154575770,
     "circulating_supply":20062562.0,"max_supply":21000000.0}
    """#.utf8)

    return Group {
        if let stats = try? JSONDecoder().decode(CoinMarketStats.self, from: json) {
            CoinMarketStatsView(stats: stats, ticker: "BTC")
        }
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
