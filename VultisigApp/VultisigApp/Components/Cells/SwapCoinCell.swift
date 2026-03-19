//
//  SwapCoinCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-27.
//

import SwiftUI

struct SwapCoinCell: View {
    let coin: CoinMeta
    let balance: String?
    let balanceFiat: String?
    let isSelected: Bool

    var onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            label
        }
        .buttonStyle(.plain)
    }

    var label: some View {
        VStack(spacing: 0) {
            content
            GradientListSeparator()
        }
        .background(isSelected ? Theme.colors.bgSurface2 : Theme.colors.bgSurface1)
    }

    var content: some View {
        HStack {
            icon
            title
            chain
            Spacer()
            balanceView
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    var icon: some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 32, height: 32),
            ticker: coin.ticker,
            tokenChainLogo: !coin.isNativeToken ? coin.chain.logo : nil
        )
    }

    var title: some View {
        Text(coin.ticker)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var chain: some View {
        Text(coin.chain.name)
            .foregroundColor(Theme.colors.textSecondary)
            .font(Theme.fonts.caption10)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.bgSurface2, lineWidth: 1)
            )
    }

    @ViewBuilder
    var balanceView: some View {
        if let balance, let balanceFiat {
            VStack(alignment: .trailing, spacing: 4) {
                Text(balance)
                    .foregroundColor(Theme.colors.textPrimary)

                Text(balanceFiat)
                    .foregroundColor(Theme.colors.textTertiary)
            }
            .font(Theme.fonts.caption12)
        }
    }
}

#Preview {
    SwapCoinCell(
        coin: CoinMeta.example,
        balance: "1000",
        balanceFiat: "10",
        isSelected: true,
        onSelect: {}
    )
}
