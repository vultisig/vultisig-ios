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
    let hasSelection: Bool
    let isStale: Bool

    static let preview = CryptoWatchlistEntry(
        date: TopCryptosEntry.preview.date,
        assets: TopCryptosEntry.preview.assets,
        currency: TopCryptosEntry.preview.currency,
        hasSelection: true,
        isStale: false
    )
}

struct CryptoWatchlistProvider: TimelineProvider {
    private let service = WidgetMarketService()

    func placeholder(in _: Context) -> CryptoWatchlistEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (CryptoWatchlistEntry) -> Void) {
        guard !context.isPreview else {
            completion(.preview)
            return
        }
        Task {
            completion(await loadEntry())
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<CryptoWatchlistEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func loadEntry() async -> CryptoWatchlistEntry {
        let selection = WidgetSharedStorage.watchlistAssets()
        let hasStoredSelection = WidgetSharedStorage.hasStoredWatchlist()
        let currency = WidgetSharedStorage.currencyCode

        guard !hasStoredSelection || !selection.isEmpty else {
            return CryptoWatchlistEntry(
                date: Date(),
                assets: [],
                currency: currency,
                hasSelection: false,
                isStale: false
            )
        }

        do {
            let query: WidgetMarketQuery = hasStoredSelection
            ? .ids(selection.map(\.id))
            : .top(limit: WidgetSharedStorage.maximumWatchlistAssets)
            let result = try await service.load(query: query, currency: currency)
            return CryptoWatchlistEntry(
                date: result.updatedAt,
                assets: result.assets,
                currency: currency,
                hasSelection: true,
                isStale: result.isStale
            )
        } catch {
            return CryptoWatchlistEntry(
                date: Date(),
                assets: [],
                currency: currency,
                hasSelection: hasStoredSelection,
                isStale: false
            )
        }
    }
}

struct CryptoWatchlistWidget: Widget {
    static let kind = WidgetSharedStorage.watchlistWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CryptoWatchlistProvider()) { entry in
            CryptoWatchlistEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.background
                }
        }
        .configurationDisplayName(LocalizedStringResource("widget.watchlist"))
        .description(LocalizedStringResource("widget.watchlist.description"))
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
                Text("widget.watchlist")
                    .font(WidgetTheme.labelFont(size: 15))
                Spacer(minLength: 4)
                staleIndicator
                WidgetBrandMark(size: 18)
            }

            HStack(spacing: 10) {
                Text("widget.asset")
                    .frame(width: 104, alignment: .leading)
                Text("widget.sevenDay")
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
        VStack {
            Spacer()
            Text(unavailableKey)
                .font(WidgetTheme.labelFont(size: 12))
                .foregroundStyle(WidgetTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityLabel(Text(unavailableAccessibilityKey))
    }

    private var unavailableKey: LocalizedStringKey {
        entry.hasSelection ? "widget.marketDataUnavailable" : "widget.watchlist.configure"
    }

    private var unavailableAccessibilityKey: LocalizedStringKey {
        entry.hasSelection ? "widget.watchlist.marketDataUnavailable" : "widget.watchlist.configure"
    }

    @ViewBuilder
    private var staleIndicator: some View {
        if entry.isStale {
            Image(systemName: "clock.arrow.circlepath")
                .font(WidgetTheme.iconFont(size: 10))
                .foregroundStyle(WidgetTheme.tertiaryText)
                .accessibilityLabel(Text("widget.cached"))
        }
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
