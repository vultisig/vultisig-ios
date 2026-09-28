//
//  WidgetMarketRow.swift
//  VultisigWidgets
//

import SwiftUI

struct WidgetMarketRow: View {
    let asset: WidgetMarketAsset
    let currency: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 8 : 10) {
            HStack(spacing: isCompact ? 8 : 10) {
                AsyncImageView(
                    logo: asset.iconLogo,
                    size: CGSize(
                        width: isCompact ? 30 : 34,
                        height: isCompact ? 30 : 34
                    ),
                    ticker: asset.symbol,
                    tokenChainLogo: nil,
                    imageData: asset.iconData
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(asset.symbol)
                        .font(WidgetTheme.labelFont(size: isCompact ? 13 : 14))
                        .foregroundStyle(WidgetTheme.primaryText)
                        .lineLimit(1)
                    Text(asset.name)
                        .font(WidgetTheme.labelFont(size: isCompact ? 10 : 11))
                        .foregroundStyle(WidgetTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: 104, alignment: .leading)

            chartColumn

            VStack(alignment: .trailing, spacing: 1) {
                Text(WidgetMarketFormatting.price(asset.currentPrice, currency: currency))
                    .font(WidgetTheme.priceFont(size: isCompact ? 12 : 13))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    if let finiteChange {
                        Image(systemName: changeSymbol(for: finiteChange))
                            .font(WidgetTheme.iconFont(size: 7, weight: .bold))
                    }
                    Text(WidgetMarketFormatting.change(finiteChange))
                        .font(WidgetTheme.labelFont(size: isCompact ? 10 : 10.5))
                        .foregroundStyle(changeColor)
                        .lineLimit(1)
                }
                .foregroundStyle(changeColor)
            }
            .frame(width: 104, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var chartColumn: some View {
        Group {
            if Self.hasUsableSparkline(asset.sparkline) {
                WidgetSparkline(
                    values: usableSparklineValues,
                    isPositive: finiteChange.map { $0 >= 0 },
                    lineWidth: isCompact ? 1.5 : 1.7
                )
                .accessibilityLabel(Text("widget.sevenDay"))
            } else {
                Text("widgetNoAvailableData")
                    .font(WidgetTheme.labelFont(size: isCompact ? 9 : 10))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(Text("widgetNoAvailableData"))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 28 : 34)
    }

    private var changeColor: Color {
        guard let change = finiteChange else { return WidgetTheme.secondaryText }
        return change >= 0 ? WidgetTheme.positive : WidgetTheme.negative
    }

    private func changeSymbol(for change: Double) -> String {
        change >= 0
            ? "arrowtriangle.up.fill"
            : "arrowtriangle.down.fill"
    }

    private var finiteChange: Double? {
        guard let change = asset.priceChangePercentage24h, change.isFinite else { return nil }
        return change
    }

    private var usableSparklineValues: [Double] {
        asset.sparkline.filter(\.isFinite)
    }

    private static func hasUsableSparkline(_ values: [Double]) -> Bool {
        values.filter(\.isFinite).count > 1
    }

    private var accessibilityLabel: String {
        let price = WidgetMarketFormatting.price(asset.currentPrice, currency: currency)
        let change = WidgetMarketFormatting.accessibilityChange(asset.priceChangePercentage24h)
        let assetLabel = String(
            format: String(localized: "widget.accessibility.asset"),
            locale: .current,
            asset.name,
            asset.symbol,
            price,
            change
        )

        guard Self.hasUsableSparkline(asset.sparkline) else {
            return [
                assetLabel,
                String(localized: "widgetNoAvailableData")
            ].joined(separator: ", ")
        }

        return assetLabel
    }
}

#if DEBUG
struct WidgetMarketRowPreviews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            WidgetMarketRow(asset: asset(sparkline: []), currency: "USD", isCompact: true)
            WidgetMarketRow(asset: asset(sparkline: [4_200]), currency: "USD", isCompact: true)
            WidgetMarketRow(asset: asset(sparkline: [4_100, 4_180, 4_240]), currency: "USD", isCompact: true)
        }
        .padding()
        .background(WidgetTheme.background)
        .previewLayout(.sizeThatFits)
    }

    private static func asset(sparkline: [Double]) -> WidgetMarketAsset {
        WidgetMarketAsset(
            id: "ethereum",
            symbol: "ETH",
            name: "Ethereum",
            imageURL: nil,
            iconData: nil,
            currentPrice: 4_200,
            priceChangePercentage24h: 1.5,
            marketCapRank: 2,
            sparkline: sparkline
        )
    }
}
#endif
