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
    /// Whether to show a small "via SwapKit" capsule next to the chain pill.
    /// Set by `SwapCoinPickerView` for destination tokens that were surfaced
    /// exclusively via SwapKit's `/tokens` list (not already in the curated
    /// allowlist + 1inch + Jupiter union).
    let isSwapKitOnly: Bool

    var onSelect: () -> Void

    init(
        coin: CoinMeta,
        balance: String?,
        balanceFiat: String?,
        isSelected: Bool,
        isSwapKitOnly: Bool = false,
        onSelect: @escaping () -> Void
    ) {
        self.coin = coin
        self.balance = balance
        self.balanceFiat = balanceFiat
        self.isSelected = isSelected
        self.isSwapKitOnly = isSwapKitOnly
        self.onSelect = onSelect
    }

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
        HStack(spacing: 8) {
            icon
            title
            chain
            if isSwapKitOnly {
                swapKitTag
            }
            Spacer()
            balanceView
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    var swapKitTag: some View {
        Text("swapPickerViaSwapKit".localized)
            .foregroundStyle(Theme.colors.textSecondary)
            .font(Theme.fonts.caption10)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.bgSurface2, lineWidth: 1)
            )
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
