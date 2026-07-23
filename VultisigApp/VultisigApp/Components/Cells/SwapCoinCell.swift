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

    init(
        coin: CoinMeta,
        balance: String?,
        balanceFiat: String?,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.coin = coin
        self.balance = balance
        self.balanceFiat = balanceFiat
        self.isSelected = isSelected
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
            Separator(color: Theme.colors.borderLight, opacity: 1)
        }
        .background(isSelected ? Theme.colors.bgSurface2 : Theme.colors.bgSurface1)
    }

    var content: some View {
        HStack(spacing: 8) {
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
            .foregroundStyle(Theme.colors.textPrimary)
    }

    @ViewBuilder
    var chain: some View {
        // A secured asset's chain is THORChain, but that reads as misleading
        // ("USDC · THORChain") — it settles on THORChain but represents an L1
        // asset. Show the L1 chain + a "Secured" badge instead, so the row
        // reads e.g. "USDC · ETH · Secured".
        if THORChainHelper.isSecuredAsset(coinMeta: coin) {
            HStack(spacing: 6) {
                chainPill(text: THORChainHelper.securedAssetChain(coinMeta: coin))
                securedBadge
            }
        } else {
            chainPill(text: coin.chain.name)
        }
    }

    func chainPill(text: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.colors.textSecondary)
            .font(Theme.fonts.caption10)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.bgSurface2, lineWidth: 1)
            )
    }

    var securedBadge: some View {
        Text("swapSecuredAssetBadge".localized)
            .foregroundStyle(Theme.colors.alertInfo)
            .font(Theme.fonts.caption10)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.alertInfo, lineWidth: 1)
            )
    }

    @ViewBuilder
    var balanceView: some View {
        if let balance, let balanceFiat {
            VStack(alignment: .trailing, spacing: 4) {
                Text(balance)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text(balanceFiat)
                    .foregroundStyle(Theme.colors.textTertiary)
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
