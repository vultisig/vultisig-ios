//
//  TopCryptosWidget.swift
//  VultisigWidgets
//

import SwiftUI
import WidgetKit

struct TopCryptosEntry: TimelineEntry {
    let date: Date
    let assets: [WidgetMarketAsset]
    let currency: String
    let isStale: Bool

    static let preview = TopCryptosEntry(
        date: Date(),
        assets: [
            CryptoTickerEntry.preview.asset,
            WidgetMarketAsset(
                id: "ethereum",
                symbol: "ETH",
                name: "Ethereum",
                imageURL: nil,
                iconData: nil,
                currentPrice: 2_501.44,
                priceChangePercentage24h: -1.25,
                marketCapRank: 2,
                sparkline: [2_610, 2_590, 2_620, 2_570, 2_540, 2_555, 2_501]
            ),
            WidgetMarketAsset(
                id: "tether",
                symbol: "USDT",
                name: "Tether",
                imageURL: nil,
                iconData: nil,
                currentPrice: 1,
                priceChangePercentage24h: 0.01,
                marketCapRank: 3,
                sparkline: [1, 1.0001, 0.9998, 1.0002, 1, 1.0001, 1]
            ),
            WidgetMarketAsset(
                id: "binancecoin",
                symbol: "BNB",
                name: "BNB",
                imageURL: nil,
                iconData: nil,
                currentPrice: 812.32,
                priceChangePercentage24h: 2.12,
                marketCapRank: 4,
                sparkline: [780, 788, 785, 797, 802, 806, 812]
            ),
            WidgetMarketAsset(
                id: "solana",
                symbol: "SOL",
                name: "Solana",
                imageURL: nil,
                iconData: nil,
                currentPrice: 147.18,
                priceChangePercentage24h: 1.43,
                marketCapRank: 5,
                sparkline: [139, 141, 140, 143, 145, 144, 147]
            )
        ].compactMap { $0 },
        currency: "USD",
        isStale: false
    )
}

struct TopCryptosProvider: TimelineProvider {
    private let service = WidgetMarketService()

    func placeholder(in _: Context) -> TopCryptosEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (TopCryptosEntry) -> Void) {
        guard !context.isPreview else {
            completion(.preview)
            return
        }
        Task {
            completion(await loadEntry())
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TopCryptosEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func loadEntry() async -> TopCryptosEntry {
        let currency = WidgetSharedStorage.currencyCode
        do {
            let result = try await service.load(query: .top(limit: 5), currency: currency)
            return TopCryptosEntry(
                date: result.updatedAt,
                assets: result.assets,
                currency: currency,
                isStale: result.isStale
            )
        } catch {
            return TopCryptosEntry(date: Date(), assets: [], currency: currency, isStale: false)
        }
    }
}

struct TopCryptosWidget: Widget {
    static let kind = "com.vultisig.widget.top-cryptos"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TopCryptosProvider()) { entry in
            TopCryptosEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.background
                }
        }
        .configurationDisplayName(LocalizedStringResource("widget.topCryptos"))
        .description(LocalizedStringResource("widget.topCryptos.description"))
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TopCryptosEntryView: View {
    let entry: TopCryptosEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if family == .systemLarge {
                header
            }

            if entry.assets.isEmpty {
                unavailableContent
            } else {
                rows
            }
        }
        .padding(contentMargins)
        .foregroundStyle(WidgetTheme.primaryText)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("widget.topCryptos")
                    .font(WidgetTheme.labelFont(size: 15))
                Spacer(minLength: 4)
                staleIndicator
                WidgetBrandMark(size: 18)
            }

            HStack(spacing: 10) {
                Text("widget.asset")
                    .frame(width: 104, alignment: .leading)
                Text("7D")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("widget.price")
                    .frame(width: 104, alignment: .trailing)
            }
            .font(WidgetTheme.labelFont(size: 10))
            .foregroundStyle(WidgetTheme.tertiaryText)
        }
        .padding(.bottom, 7)
        .accessibilityElement(children: .combine)
    }

    private var rows: some View {
        let isCompact = family == .systemMedium
        let assets = entry.assets.prefix(isCompact ? 3 : 5)

        return VStack(spacing: 0) {
            ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                if index > 0 {
                    Rectangle()
                        .fill(WidgetTheme.separator)
                        .frame(height: 1)
                }

                WidgetMarketRow(
                    asset: asset,
                    currency: entry.currency,
                    isCompact: isCompact
                )
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text("widget.marketDataUnavailable")
                .font(WidgetTheme.labelFont(size: 12))
                .foregroundStyle(WidgetTheme.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("widget.topMarketDataUnavailable"))
    }

    @ViewBuilder
    private var staleIndicator: some View {
        if entry.isStale {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetTheme.tertiaryText)
                .accessibilityLabel(Text("widget.cached"))
        }
    }
}

#if DEBUG
struct TopCryptosWidgetPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            TopCryptosEntryView(entry: .preview)
                .containerBackground(for: .widget) { WidgetTheme.background }
                .previewContext(WidgetPreviewContext(family: .systemMedium))

            TopCryptosEntryView(entry: .preview)
                .containerBackground(for: .widget) { WidgetTheme.background }
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
