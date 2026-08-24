//
//  WidgetMarketRow.swift
//  VultisigWidgets
//

import SwiftUI

struct WidgetMarketRow: View {
    let asset: WidgetMarketAsset
    let currency: String
    let showsChange: Bool
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 7 : 10) {
            WidgetTokenIcon(asset: asset, size: isCompact ? 22 : 28)

            VStack(alignment: .leading, spacing: 0) {
                Text(asset.symbol)
                    .font(WidgetTheme.labelFont(size: isCompact ? 11 : 13))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                Text(asset.name)
                    .font(WidgetTheme.labelFont(size: isCompact ? 9 : 10))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: isCompact ? 62 : 72, alignment: .leading)

            WidgetSparkline(
                values: asset.sparkline,
                isPositive: (asset.priceChangePercentage24h ?? 0) >= 0,
                lineWidth: isCompact ? 1.4 : 1.7
            )
            .frame(maxWidth: .infinity, maxHeight: isCompact ? 22 : 30)

            VStack(alignment: .trailing, spacing: 1) {
                Text(WidgetMarketFormatting.price(asset.currentPrice, currency: currency))
                    .font(WidgetTheme.priceFont(size: isCompact ? 11 : 13))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                if showsChange {
                    Text(WidgetMarketFormatting.change(asset.priceChangePercentage24h))
                        .font(WidgetTheme.labelFont(size: 9))
                        .foregroundStyle(changeColor)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: isCompact ? 74 : 84, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var changeColor: Color {
        guard let change = asset.priceChangePercentage24h else { return WidgetTheme.secondaryText }
        return change >= 0 ? WidgetTheme.positive : WidgetTheme.negative
    }

    private var accessibilityLabel: String {
        let price = WidgetMarketFormatting.price(asset.currentPrice, currency: currency)
        let change = WidgetMarketFormatting.change(asset.priceChangePercentage24h)
        return String(
            format: String(localized: "widget.accessibility.asset"),
            locale: .current,
            asset.name,
            asset.symbol,
            price,
            change
        )
    }
}
