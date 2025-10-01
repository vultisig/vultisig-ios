//
//  VaultChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VaultChainCellView: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault
    var onCopy: () -> Void
    var onAction: () -> Void
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @StateObject var viewModel = ChainCellViewModel()
    
    var trailingSubtitle: String {
        group.coins.count > 1 ? "\(group.coins.count) \("assets".localized)" : group.nativeCoin.balanceStringWithTicker
    }
    
    var body: some View {
        Button(action: onAction) {
            HStack {
                HStack(spacing: 12) {
                    AsyncImageView(
                        logo: group.logo,
                        size: CGSize(width: 36, height: 36),
                        ticker: group.chain.ticker,
                        tokenChainLogo: group.chain.logo
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Button(action: onCopy) {
                            HStack(spacing: 4) {
                                Text(group.truncatedAddress)
                                    .font(Theme.fonts.caption12)
                                    .foregroundStyle(Theme.colors.textExtraLight)
                                Icon(named: "copy", color: Theme.colors.textExtraLight, size: 12)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                
                HStack(spacing: 8) {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : group.totalBalanceInFiatString)
                            .font(Theme.fonts.priceBodyS)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : trailingSubtitle)
                            .font(Theme.fonts.priceCaption)
                            .foregroundStyle(Theme.colors.textExtraLight)
                    }
                    Icon(named: "chevron-down-small", color: Theme.colors.textPrimary, size: 16)
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSecondary)
        .buttonStyle(.plain)
    }
}

#Preview {
    VaultChainCellView(group: .example, vault: .example) {
    } onAction: {
    }.environmentObject(HomeViewModel())
}
