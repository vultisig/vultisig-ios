//
//  TokenCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct TokenCellView: View {
    @ObservedObject var coin: Coin
    @EnvironmentObject var homeViewModel: HomeViewModel

    /// Shown for an XRPL issued currency the account holds no trust line for.
    /// The coin is added locally the moment the user picks it (like every other
    /// chain), but on XRPL it cannot hold or receive a balance until a TrustSet
    /// opens the line — so the row has to make that state legible and offer the
    /// one action that fixes it. `nil` for every other coin.
    var onActivate: (() -> Void)?

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 36, height: 36),
                    ticker: coin.chain.ticker,
                    tokenChainLogo: coin.tokenChainLogo
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(coin.ticker)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(Decimal(coin.price).formatToFiatPrice())
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.colors.bgSurface2))
                        .fixedSize()
                        .contentTransition(.numericText())
                        .animation(.interpolatingSpring, value: coin.price)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                if let onActivate {
                    PrimaryButton(
                        title: "rippleTrustLineActivateAction".localized,
                        size: .mini,
                        action: onActivate
                    )
                    .fixedSize()
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : coin.balanceInFiatForDisplay)
                            .font(Theme.fonts.priceBodyS)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.interpolatingSpring, value: coin.balanceInFiatForDisplay)
                        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : coin.balanceStringWithTicker)
                            .font(Theme.fonts.priceCaption)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .contentTransition(.numericText())
                            .animation(.interpolatingSpring, value: coin.balanceStringWithTicker)
                    }
                }
                Icon(.chevronRightSmall, color: Theme.colors.textPrimary, size: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSurface1)
    }
}

#Preview {
    TokenCellView(coin: .example)
        .environmentObject(HomeViewModel())
}
