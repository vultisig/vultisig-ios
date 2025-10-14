//
//  ChainDetailHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ChainDetailHeaderView: View {
    @ObservedObject var vault: Vault
    @ObservedObject var group: GroupedChain
    var onCopy: () -> Void
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            chainNameView
            chainBalanceView
            chainAddressView
        }
    }
    
    var chainNameView: some View {
        HStack(spacing: 4) {
            AsyncImageView(
                logo: group.logo,
                size: CGSize(width: 24, height: 24),
                ticker: group.chain.ticker,
                tokenChainLogo: group.chain.logo
            )
            
            Text(group.name)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }
    
    var chainBalanceView: some View {
        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : group.totalBalanceInFiatString)
            .font(Theme.fonts.priceTitle1)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(height: 47)
            .contentTransition(.numericText())
            .animation(.interpolatingSpring, value: group.totalBalanceInFiatString)
    }
    
    var chainAddressView: some View {
        Button(action: onCopy) {
            HStack(spacing: 4) {
                Text(group.truncatedAddress)
                    .foregroundStyle(Color(hex: "5180FC"))
                    .font(Theme.fonts.caption12)
                Icon(
                    named: "copy",
                    color: Color(hex: "5180FC"),
                    size: 16
                )
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "5180FC").opacity(0.12)))
        }
    }
}

#Preview {
    ChainDetailHeaderView(vault: .example, group: .example, onCopy: {})
}
