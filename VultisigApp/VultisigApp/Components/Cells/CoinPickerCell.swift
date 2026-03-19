//
//  CoinPickerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-11.
//

import SwiftUI

struct CoinPickerCell: View {
    let coin: Coin

    var body: some View {
        content
    }

    var content: some View {
        HStack(spacing: 16) {
            AsyncImageView(
                logo: coin.logo,
                size: CGSize(width: 32, height: 32),
                ticker: coin.ticker,
                tokenChainLogo: coin.chain.logo
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(coin.ticker)
                    Spacer()
                    Text(coin.balanceString)
                        .font(Theme.fonts.caption12)

                    Text(coin.balanceInFiat)
                }
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)

                Text(coin.address)
                    .font(Theme.fonts.caption12)
                    .foregroundColor(Theme.colors.bgButtonPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }
}

#Preview {
    CoinPickerCell(coin: Coin.example)
}
