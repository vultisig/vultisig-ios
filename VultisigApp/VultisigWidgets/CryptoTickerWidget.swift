//
//  CryptoTickerWidget.swift
//  VultisigWidgets
//

import SwiftUI
import WidgetKit

struct FoundationTickerEntry: TimelineEntry {
    let date: Date
    let symbol: String
    let name: String
    let price: String
    let change: String
    let isPositive: Bool
    let sparkline: [Double]

    static let preview = FoundationTickerEntry(
        date: Date(),
        symbol: "BTC",
        name: "Bitcoin",
        price: "$79,910.00",
        change: "+3.54% 24H",
        isPositive: true,
        sparkline: [
            74_800, 75_300, 75_050, 75_900, 76_150, 75_700,
            76_600, 76_350, 77_200, 77_750, 77_100, 77_900,
            78_250, 78_050, 78_800, 79_050, 79_910
        ]
    )
}

struct FoundationTickerProvider: TimelineProvider {
    func placeholder(in _: Context) -> FoundationTickerEntry {
        .preview
    }

    func getSnapshot(in _: Context, completion: @escaping (FoundationTickerEntry) -> Void) {
        completion(.preview)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<FoundationTickerEntry>) -> Void) {
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [.preview], policy: .after(refresh)))
    }
}

struct CryptoTickerWidget: Widget {
    static let kind = "com.vultisig.widget.crypto-ticker"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FoundationTickerProvider()) { entry in
            CryptoTickerEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.background
                }
        }
        .configurationDisplayName("Crypto Ticker")
        .description("Track the price and seven-day trend of a cryptocurrency.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct CryptoTickerEntryView: View {
    let entry: FoundationTickerEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumContent
            } else {
                smallContent
            }
        }
        .padding(contentMargins)
        .foregroundStyle(WidgetTheme.primaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tokenIcon(size: 28)
                identity
                Spacer(minLength: 4)
                WidgetBrandMark(size: 18)
            }

            Spacer(minLength: 0)

            Text(entry.price)
                .font(WidgetTheme.priceFont(size: 21))
                .minimumScaleFactor(0.78)
                .lineLimit(1)

            Text(entry.change)
                .font(WidgetTheme.labelFont(size: 12))
                .foregroundStyle(changeColor)
                .lineLimit(1)
        }
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tokenIcon(size: 30)
                identity
                Spacer(minLength: 8)
                Text("7D")
                    .font(WidgetTheme.labelFont(size: 11))
                    .foregroundStyle(WidgetTheme.secondaryText)
                WidgetBrandMark(size: 18)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.price)
                    .font(WidgetTheme.priceFont(size: 22))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text(entry.change)
                    .font(WidgetTheme.labelFont(size: 12))
                    .foregroundStyle(changeColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            WidgetSparkline(values: entry.sparkline, isPositive: entry.isPositive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.symbol)
                .font(WidgetTheme.labelFont(size: 14))
                .lineLimit(1)
            Text(entry.name)
                .font(WidgetTheme.labelFont(size: 11))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
        }
    }

    private var changeColor: Color {
        entry.isPositive ? WidgetTheme.positive : WidgetTheme.negative
    }

    private func tokenIcon(size: CGFloat) -> some View {
        Image("BitcoinLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        let direction = entry.isPositive ? "up" : "down"
        return "\(entry.name), \(entry.symbol), \(entry.price), \(direction) \(entry.change), seven day trend, updated now"
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
