//
//  GroupedChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct GroupedChainCellView: View {
    let chain: Chain
    let address: String
    let fiatBalance: String
    let cryptoBalance: String
    let assetCount: Int
    /// When provided, replaces the default `N assets` / `cryptoBalance` subtitle.
    /// Used by DeFi rows to render `"%d positions"` / "No positions found" instead
    /// of wallet asset counts. The override is rendered with the small caption font
    /// (matching multi-asset spacing).
    var trailingSubtitleOverride: String?
    var onCopy: (() -> Void)?

    @EnvironmentObject var homeViewModel: HomeViewModel

    private var truncatedAddress: String {
        guard address.count > 8 else { return address }
        return address.prefix(4) + "..." + address.suffix(4)
    }

    private var showAssetCount: Bool {
        trailingSubtitleOverride == nil && assetCount > 1
    }

    private var trailingSubtitle: String {
        if homeViewModel.hideVaultBalance {
            return String.hideBalanceText
        }
        if let trailingSubtitleOverride {
            return trailingSubtitleOverride
        }
        return showAssetCount ? "\(assetCount) \("assets".localized)" : cryptoBalance
    }

    private var trailingSubtitleFont: Font {
        (showAssetCount && !homeViewModel.hideVaultBalance) ? Theme.fonts.priceCaption : Theme.fonts.caption12
    }

    private var fiatBalanceText: String {
        homeViewModel.hideVaultBalance ? String.hideBalanceText : fiatBalance
    }

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: chain.logo,
                    size: CGSize(width: 36, height: 36),
                    ticker: chain.ticker,
                    tokenChainLogo: chain.logo
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(chain.name)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    if let onCopy {
                        Button(action: onCopy) {
                            HStack(spacing: 4) {
                                Text(truncatedAddress)
                                    .font(Theme.fonts.caption12)
                                    .foregroundStyle(Theme.colors.textTertiary)
                                Icon(named: "copy", color: Theme.colors.textTertiary, size: 12)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    AmountText(fiatBalanceText)
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .contentTransition(.numericText())
                    Text(trailingSubtitle)
                        .font(trailingSubtitleFont)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .contentTransition(.numericText())
                }
                // Drive the balance Texts' content transition only when the
                // hide/show-balance toggle flips. Scoping the animation to
                // `hideVaultBalance` keeps the row body un-animated on scroll
                // and balance refresh (the projection's perf goal) while
                // restoring the spring the pre-projection cell used on toggle.
                .animation(.interpolatingSpring, value: homeViewModel.hideVaultBalance)
                Icon(named: "chevron-right-small", color: Theme.colors.textPrimary, size: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSurface1)
        .buttonStyle(.plain)
    }
}

#Preview {
    GroupedChainCellView(
        chain: .bitcoin,
        address: "",
        fiatBalance: "",
        cryptoBalance: "",
        assetCount: 1,
        onCopy: {}
    ).environmentObject(HomeViewModel())
}
