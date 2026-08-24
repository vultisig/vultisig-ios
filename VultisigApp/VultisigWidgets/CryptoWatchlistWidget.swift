//
//  CryptoWatchlistWidget.swift
//  VultisigWidgets
//

import SwiftUI
import WidgetKit

struct CryptoWatchlistEntry: TimelineEntry {
    let date: Date
    let assets: [WidgetMarketAsset]
    let currency: String
    let isStale: Bool

    static let preview = CryptoWatchlistEntry(
        date: TopCryptosEntry.preview.date,
        assets: TopCryptosEntry.preview.assets,
        currency: TopCryptosEntry.preview.currency,
        isStale: false
    )
}

struct CryptoWatchlistProvider: AppIntentTimelineProvider {
    private static let defaultIDs = ["bitcoin", "ethereum", "solana"]
    private let service = WidgetMarketService()

    func placeholder(in _: Context) -> CryptoWatchlistEntry {
        .preview
    }

    func snapshot(
        for configuration: WatchlistConfigurationIntent,
        in context: Context
    ) async -> CryptoWatchlistEntry {
        if context.isPreview {
            return .preview
        }
        return await loadEntry(configuration: configuration)
    }

    func timeline(
        for configuration: WatchlistConfigurationIntent,
        in _: Context
    ) async -> Timeline<CryptoWatchlistEntry> {
        let entry = await loadEntry(configuration: configuration)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func loadEntry(configuration: WatchlistConfigurationIntent) async -> CryptoWatchlistEntry {
        let ids = configuration.selectedIDs.isEmpty ? Self.defaultIDs : configuration.selectedIDs
        let currency = WidgetSharedStorage.currencyCode

        do {
            let result = try await service.load(query: .ids(ids), currency: currency)
            return CryptoWatchlistEntry(
                date: result.updatedAt,
                assets: result.assets,
                currency: currency,
                isStale: result.isStale
            )
        } catch {
            return CryptoWatchlistEntry(date: Date(), assets: [], currency: currency, isStale: false)
        }
    }
}

struct CryptoWatchlistWidget: Widget {
    static let kind = "com.vultisig.widget.crypto-watchlist"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: WatchlistConfigurationIntent.self,
            provider: CryptoWatchlistProvider()
        ) { entry in
            CryptoWatchlistEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.background
                }
        }
        .configurationDisplayName("Crypto Watchlist")
        .description("Follow up to five cryptocurrencies in your preferred order.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct CryptoWatchlistEntryView: View {
    let entry: CryptoWatchlistEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Watchlist")
                .font(WidgetTheme.labelFont(size: family == .systemMedium ? 13 : 15))
            Text("7D • \(entry.currency.uppercased())")
                .font(WidgetTheme.labelFont(size: 9))
                .foregroundStyle(WidgetTheme.tertiaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            WidgetBrandMark(size: 18)
        }
        .padding(.bottom, family == .systemMedium ? 5 : 9)
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
                    showsChange: !isCompact,
                    isCompact: isCompact
                )
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text("Watchlist data is temporarily unavailable")
                .font(WidgetTheme.labelFont(size: 12))
                .foregroundStyle(WidgetTheme.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Crypto watchlist data is temporarily unavailable")
    }
}

#if DEBUG
struct CryptoWatchlistWidgetPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            CryptoWatchlistEntryView(entry: .preview)
                .containerBackground(for: .widget) { WidgetTheme.background }
                .previewContext(WidgetPreviewContext(family: .systemMedium))

            CryptoWatchlistEntryView(entry: .preview)
                .containerBackground(for: .widget) { WidgetTheme.background }
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
