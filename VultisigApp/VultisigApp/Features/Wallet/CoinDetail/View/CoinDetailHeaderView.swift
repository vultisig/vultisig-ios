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
            pendingBalanceView
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
        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : coin.balanceInFiatForDisplay)
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

    /// Money arriving that the wallet cannot spend yet, reported separately
    /// from the balance above it. The balance is strictly what a transaction
    /// can be funded from, so an inbound payment still in the mempool does not
    /// move it — without this line the recipient sees nothing at all happen
    /// until the transaction confirms. Absent entirely when there is nothing
    /// pending, and hidden with the rest of the numbers when balances are.
    @ViewBuilder
    var pendingBalanceView: some View {
        if coin.hasPendingBalance, !homeViewModel.hideVaultBalance {
            Text(String(format: "pendingIncomingBalance".localized, coin.pendingBalanceStringWithTicker))
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }
}

#Preview {
    CoinDetailHeaderView(coin: .example)
        .environmentObject(HomeViewModel())
}
