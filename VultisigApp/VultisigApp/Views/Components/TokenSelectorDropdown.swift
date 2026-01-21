//
//  TokenSelectorDropdown.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct TokenSelectorDropdown: View {
    let coin: Coin
    let balance: String? = nil
    let onPress: (() -> Void)?

    var body: some View {
        cell
            .onTapGesture {
                onPress?()
            }
    }

    var cell: some View {
        HStack(spacing: 10) {
            image
            ticker
            Spacer()
            balanceContent
            arrow
        }
        .redacted(reason: coin.balanceString.isEmpty ? .placeholder : [])
        .font(Theme.fonts.bodyMRegular)
        .foregroundColor(Theme.colors.textPrimary)
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }

    var image: some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 32, height: 32),
            ticker: coin.ticker,
            tokenChainLogo: coin.chain.logo
        )
    }

    var ticker: some View {
        Text("\(coin.ticker)")
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var arrow: some View {
        Image("arrow")
            .frame(width: 20, height: 20)
    }

    var balanceContent: some View {
        HStack(spacing: 0) {
            Group {
                Text(NSLocalizedString("balance", comment: "")) +
                Text(": ")
            }

            if let balance {
                Text(balance)
            } else {
                Text(coin.balanceString)
            }
        }
        .font(Theme.fonts.caption12)
        .foregroundColor(Theme.colors.textSecondary)
    }

}

#Preview {
    ZStack {
        Background()
        TokenSelectorDropdown(coin: .example, onPress: nil)
    }
}
