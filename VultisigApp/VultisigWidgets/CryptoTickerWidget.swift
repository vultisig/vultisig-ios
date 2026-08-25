//
//  CryptoTickerWidget.swift
//  VultisigWidgets
//

import SwiftUI
import WidgetKit

struct CryptoTickerEntry: TimelineEntry {
    let date: Date
    let asset: WidgetMarketAsset?
    let currency: String
    let isStale: Bool

    static let preview = CryptoTickerEntry(
        date: Date(),
        asset: WidgetMarketAsset(
            id: "bitcoin",
            symbol: "BTC",
            name: "Bitcoin",
            imageURL: nil,
            iconData: nil,
            currentPrice: 79_910,
            priceChangePercentage24h: 3.54,
            marketCapRank: 1,
            sparkline: [
                74_800, 75_300, 75_050, 75_900, 76_150, 75_700,
                76_600, 76_350, 77_200, 77_750, 77_100, 77_900,
                78_250, 78_050, 78_800, 79_050, 79_910
            ]
        ),
        currency: "USD",
        isStale: false
    )
}

struct CryptoTickerProvider: AppIntentTimelineProvider {
    private let service = WidgetMarketService()

    func placeholder(in _: Context) -> CryptoTickerEntry {
        .preview
    }

    func snapshot(
        for configuration: CryptoTickerConfigurationIntent,
        in context: Context
    ) async -> CryptoTickerEntry {
        if context.isPreview {
            return .preview
        }
        return await loadEntry(configuration: configuration)
    }

    func timeline(
        for configuration: CryptoTickerConfigurationIntent,
        in _: Context
    ) async -> Timeline<CryptoTickerEntry> {
        let entry = await loadEntry(configuration: configuration)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func loadEntry(configuration: CryptoTickerConfigurationIntent) async -> CryptoTickerEntry {
        let id = configuration.asset?.id ?? WidgetCryptoAssetEntity.bitcoin.id
        let currency = WidgetSharedStorage.currencyCode

        do {
            let result = try await service.load(query: .ids([id]), currency: currency)
            return CryptoTickerEntry(
                date: result.updatedAt,
                asset: result.assets.first,
                currency: currency,
                isStale: result.isStale
            )
        } catch {
            return CryptoTickerEntry(date: Date(), asset: nil, currency: currency, isStale: false)
        }
    }
}

struct CryptoTickerWidget: Widget {
    static let kind = "com.vultisig.widget.crypto-ticker"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: CryptoTickerConfigurationIntent.self,
            provider: CryptoTickerProvider()
        ) { entry in
            CryptoTickerEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.background
                }
        }
        .configurationDisplayName(LocalizedStringResource("widget.cryptoTicker"))
        .description(LocalizedStringResource("widget.cryptoTicker.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct CryptoTickerEntryView: View {
    let entry: CryptoTickerEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        Group {
            if let asset = entry.asset {
                if family == .systemMedium {
                    mediumContent(asset)
                } else {
                    smallContent(asset)
                }
            } else {
                unavailableContent
            }
        }
        .padding(contentMargins)
        .foregroundStyle(WidgetTheme.primaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func smallContent(_ asset: WidgetMarketAsset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tokenIcon(asset, size: 28)
                identity(asset)
                Spacer(minLength: 4)
                staleIndicator
                WidgetBrandMark(size: 18)
            }

            Spacer(minLength: 0)

            Text(price(asset))
                .font(WidgetTheme.priceFont(size: 21))
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            Text(change(asset))
                .font(WidgetTheme.labelFont(size: 12))
                .foregroundStyle(changeColor(asset))
                .lineLimit(1)
        }
    }

    private func mediumContent(_ asset: WidgetMarketAsset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tokenIcon(asset, size: 30)
                identity(asset)
                Spacer(minLength: 8)
                Text("7D")
                    .font(WidgetTheme.labelFont(size: 11))
                    .foregroundStyle(WidgetTheme.secondaryText)
                staleIndicator
                WidgetBrandMark(size: 18)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(price(asset))
                    .font(WidgetTheme.priceFont(size: 22))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(change(asset))
                    .font(WidgetTheme.labelFont(size: 12))
                    .foregroundStyle(changeColor(asset))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            WidgetSparkline(
                values: asset.sparkline,
                isPositive: (asset.priceChangePercentage24h ?? 0) >= 0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func identity(_ asset: WidgetMarketAsset) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(asset.symbol)
                .font(WidgetTheme.labelFont(size: 14))
                .lineLimit(1)
            Text(asset.name)
                .font(WidgetTheme.labelFont(size: 11))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
        }
    }

    private func tokenIcon(_ asset: WidgetMarketAsset, size: CGFloat) -> some View {
        AsyncImageView(
            logo: asset.iconLogo,
            size: CGSize(width: size, height: size),
            ticker: asset.symbol,
            tokenChainLogo: nil,
            imageData: asset.iconData
        )
        .accessibilityHidden(true)
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("widget.marketData")
                    .font(WidgetTheme.labelFont(size: 14))
                Spacer()
                WidgetBrandMark(size: 18)
            }
            Spacer()
            Text("widget.temporarilyUnavailable")
                .font(WidgetTheme.labelFont(size: 12))
                .foregroundStyle(WidgetTheme.secondaryText)
        }
    }

    private func price(_ asset: WidgetMarketAsset) -> String {
        WidgetMarketFormatting.price(asset.currentPrice, currency: entry.currency)
    }

    private func change(_ asset: WidgetMarketAsset) -> String {
        WidgetMarketFormatting.change(asset.priceChangePercentage24h)
    }

    private func changeColor(_ asset: WidgetMarketAsset) -> Color {
        guard let change = asset.priceChangePercentage24h else { return WidgetTheme.secondaryText }
        return change >= 0 ? WidgetTheme.positive : WidgetTheme.negative
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

    private var accessibilityLabel: String {
        guard let asset = entry.asset else { return String(localized: "widget.cryptoMarketDataUnavailable") }
        let direction = (asset.priceChangePercentage24h ?? 0) >= 0
            ? String(localized: "widget.up")
            : String(localized: "widget.down")
        let freshness = entry.isStale
            ? String(localized: "widget.cachedData")
            : String(localized: "widget.updatedData")
        return String(
            format: String(localized: "widget.accessibility.ticker"),
            locale: .current,
            asset.name,
            asset.symbol,
            price(asset),
            direction,
            change(asset),
            freshness
        )
    }
}

#if DEBUG
struct CryptoTickerWidgetPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            CryptoTickerEntryView(entry: .preview)
                .containerBackground(for: .widget) { WidgetTheme.background }
                .previewContext(WidgetPreviewContext(family: .systemSmall))

            CryptoTickerEntryView(entry: .preview)
                .containerBackground(for: .widget) { WidgetTheme.background }
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
#endif
