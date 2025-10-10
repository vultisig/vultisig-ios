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
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State private var trailingSubtitle: String = ""
    @State private var fiatBalanceText: String = ""
    @State private var hasLoaded: Bool = false
    @State private var trailingSubtitleFont: Font = Theme.fonts.priceCaption
    
    var body: some View {
        NavigationLink {
            ChainDetailScreen(group: group, vault: vault)
        } label: {
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
                        Text(fiatBalanceText)
                            .font(Theme.fonts.priceBodyS)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .if(hasLoaded) {
                                $0.contentTransition(.numericText())
                            }
                        Text(trailingSubtitle)
                            .font(trailingSubtitleFont)
                            .foregroundStyle(Theme.colors.textExtraLight)
                            .if(hasLoaded) {
                                $0.contentTransition(.numericText())
                            }
                    }
                    Icon(named: "chevron-right-small", color: Theme.colors.textPrimary, size: 16)
                }
            }
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSecondary)
        .buttonStyle(.plain)
        .onLoad(perform: updateTexts)
        .onChange(of: group.coins) { _, _ in
            updateTexts()
        }
        .onChange(of: homeViewModel.hideVaultBalance) { _, _ in
            updateTexts()
        }
    }
}

private extension VaultChainCellView {
    func updateTexts() {
        updateTrailingSubtitle()
        updateFiatBalanceText()
        
        guard !hasLoaded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            hasLoaded = true
        }
    }
    
    func updateTrailingSubtitle() {
        let showPrice = group.coins.count > 1
        let trailingSubtitle = showPrice ? "\(group.coins.count) \("assets".localized)" : group.nativeCoin.balanceStringWithTicker
        withAnimation(.interpolatingSpring) {
            self.trailingSubtitle = homeViewModel.hideVaultBalance ? String.hideBalanceText : trailingSubtitle
            self.trailingSubtitleFont = (showPrice && !homeViewModel.hideVaultBalance) ? Theme.fonts.priceCaption : Theme.fonts.caption12
        }
    }
    
    func updateFiatBalanceText() {
        withAnimation(.interpolatingSpring) {
            fiatBalanceText = homeViewModel.hideVaultBalance ? String.hideBalanceText : group.totalBalanceInFiatString
        }
    }
}

#Preview {
    VaultChainCellView(group: .example, vault: .example) {
    }
        .environmentObject(HomeViewModel())
}
