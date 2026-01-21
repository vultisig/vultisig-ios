//
//  CoinDetailHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import SwiftUI

struct CoinDetailHeaderView: View {
    @ObservedObject var coin: Coin
    @EnvironmentObject var homeViewModel: HomeViewModel

    var body: some View {
        VStack(spacing: 8) {
            chainNameView
                .padding(.bottom, 4)
            chainBalanceView
            chainFiatBalanceView
        }
    }

    var chainNameView: some View {
        HStack(spacing: 8) {
            AsyncImageView(
                logo: coin.logo,
                size: CGSize(width: 24, height: 24),
                ticker: coin.ticker,
                tokenChainLogo: nil
            )

            Text(coin.ticker)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    var chainBalanceView: some View {
        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : coin.balanceInFiat)
            .font(Theme.fonts.priceTitle1)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(height: 47)
    }

    var chainFiatBalanceView: some View {
        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : coin.balanceStringWithTicker)
            .font(Theme.fonts.subtitle)
            .foregroundStyle(Theme.colors.textTertiary)
            .frame(height: 18)
    }
}

#Preview {
    CoinDetailHeaderView(coin: .example)
        .environmentObject(HomeViewModel())
}
