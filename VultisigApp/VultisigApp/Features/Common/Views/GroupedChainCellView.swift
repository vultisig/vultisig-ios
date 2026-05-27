//
//  GroupedChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct GroupedChainCellView: View {
    let chain: Chain
    let vault: Vault
    let fiatBalance: String
    let cryptoBalance: String
    /// When provided, replaces the default `N assets` / `cryptoBalance` subtitle.
    /// Used by DeFi rows to render `"%d positions"` / "No positions found" instead
    /// of wallet asset counts. The override is rendered with the small caption font
    /// (matching multi-asset spacing).
    var trailingSubtitleOverride: String?
    var onCopy: (() -> Void)?

    @State private var trailingSubtitle: String = ""
    @State private var fiatBalanceText: String = ""
    @State private var hasLoaded: Bool = false
    @State private var trailingSubtitleFont: Font = Theme.fonts.priceCaption

    @EnvironmentObject var homeViewModel: HomeViewModel

    private var chainCoins: [Coin] { vault.coins(for: chain) }

    private var address: String { vault.address(for: chain) ?? "" }

    private var truncatedAddress: String {
        guard address.count > 8 else { return address }
        return address.prefix(4) + "..." + address.suffix(4)
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
                    Text(fiatBalanceText)
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .if(hasLoaded) {
                            $0.contentTransition(.numericText())
                        }
                    Text(trailingSubtitle)
                        .font(trailingSubtitleFont)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .if(hasLoaded) {
                            $0.contentTransition(.numericText())
                        }
                }
                Icon(named: "chevron-right-small", color: Theme.colors.textPrimary, size: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSurface1)
        .buttonStyle(.plain)
        .onLoad(perform: updateTexts)
        .onChange(of: fiatBalance) { _, _ in
            updateTexts()
        }
        .onChange(of: trailingSubtitleOverride) { _, _ in
            updateTexts()
        }
        .onChange(of: homeViewModel.hideVaultBalance) { _, _ in
            updateTexts()
        }
    }
}

private extension GroupedChainCellView {
    func updateTexts() {
        updateTrailingSubtitle()
        updateFiatBalanceText()

        guard !hasLoaded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            hasLoaded = true
        }
    }

    func updateTrailingSubtitle() {
        if let override = trailingSubtitleOverride {
            withAnimation(.interpolatingSpring) {
                self.trailingSubtitle = homeViewModel.hideVaultBalance ? String.hideBalanceText : override
                self.trailingSubtitleFont = Theme.fonts.caption12
            }
            return
        }

        let count = chainCoins.count
        let showPrice = count > 1
        let trailingSubtitle = showPrice ? "\(count) \("assets".localized)" : cryptoBalance
        withAnimation(.interpolatingSpring) {
            self.trailingSubtitle = homeViewModel.hideVaultBalance ? String.hideBalanceText : trailingSubtitle
            self.trailingSubtitleFont = (showPrice && !homeViewModel.hideVaultBalance) ? Theme.fonts.priceCaption : Theme.fonts.caption12
        }
    }

    func updateFiatBalanceText() {
        withAnimation(.interpolatingSpring) {
            fiatBalanceText = homeViewModel.hideVaultBalance ? String.hideBalanceText : fiatBalance
        }
    }
}

#Preview {
    GroupedChainCellView(
        chain: .bitcoin,
        vault: .example,
        fiatBalance: "",
        cryptoBalance: "",
        onCopy: {}
    ).environmentObject(HomeViewModel())
}
