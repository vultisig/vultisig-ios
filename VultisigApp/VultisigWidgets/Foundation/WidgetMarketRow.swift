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

            WidgetSparkline(
                values: asset.sparkline,
                isPositive: (asset.priceChangePercentage24h ?? 0) >= 0,
                lineWidth: isCompact ? 1.5 : 1.7
            )
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? 28 : 34)

            VStack(alignment: .trailing, spacing: 1) {
                Text(WidgetMarketFormatting.price(asset.currentPrice, currency: currency))
                    .font(WidgetTheme.priceFont(size: isCompact ? 12 : 13))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    if asset.priceChangePercentage24h != nil {
                        Image(systemName: changeSymbol)
                            .font(.system(size: 7, weight: .bold))
                    }
                    Text(WidgetMarketFormatting.compactChange(asset.priceChangePercentage24h))
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

    private var changeColor: Color {
        guard let change = asset.priceChangePercentage24h else { return WidgetTheme.secondaryText }
        return change >= 0 ? WidgetTheme.positive : WidgetTheme.negative
    }

    private var changeSymbol: String {
        (asset.priceChangePercentage24h ?? 0) >= 0
            ? "arrowtriangle.up.fill"
            : "arrowtriangle.down.fill"
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
