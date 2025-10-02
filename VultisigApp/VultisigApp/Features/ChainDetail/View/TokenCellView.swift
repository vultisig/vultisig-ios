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
        
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 36, height: 36),
                    ticker: coin.chain.ticker,
                    tokenChainLogo: coin.chain.logo
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(coin.ticker)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(Decimal(coin.price).formatToFiat())
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textLight)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.colors.bgTertiary))
                        .fixedSize()
                }
            }
            HStack(spacing: 8) {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : coin.balanceInFiat)
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : coin.balanceStringWithTicker)
                        .font(Theme.fonts.priceCaption)
                        .foregroundStyle(Theme.colors.textExtraLight)
                }
                Icon(named: "chevron-right-small", color: Theme.colors.textPrimary, size: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSecondary)
    }
}

#Preview {
    TokenCellView(coin: .example)
        .environmentObject(HomeViewModel())
}
