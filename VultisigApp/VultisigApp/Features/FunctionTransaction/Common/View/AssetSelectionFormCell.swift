//
//  AssetSelectionCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI

struct AssetSelectionFormCell: View {
    let coin: CoinMeta?

    var body: some View {
        if let coin {
            HStack(spacing: 4) {
                AsyncImageView(
                    logo: coin.logo,
                    size: .init(width: 36, height: 36),
                    ticker: coin.ticker,
                    tokenChainLogo: nil
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(coin.ticker)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text("native".localized)
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .showIf(coin.isNativeToken)
                }

                Icon(
                    named: "chevron-right",
                    color: Theme.colors.textPrimary,
                    size: 20
                )
            }
            .padding(.vertical, 6)
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .background(RoundedRectangle(cornerRadius: 99).fill(Theme.colors.bgSurface1))
        }
    }
}

#Preview {
    AssetSelectionFormCell(coin: .example)
}
