//
//  TokenSelectionGridCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct TokenSelectionGridCell: View {
    let coin: CoinMeta
    let name: String?
    let showChainIcon: Bool
    let verification: TokenVerification
    var onSelection: (Bool) -> Void

    @State var isSelected: Bool

    init(
        coin: CoinMeta,
        name: String? = nil,
        showChainIcon: Bool = false,
        verification: TokenVerification = .curated,
        isSelected: Bool,
        onSelection: @escaping (Bool) -> Void
    ) {
        self.coin = coin
        self.name = name
        self.showChainIcon = showChainIcon
        self.verification = verification
        self.isSelected = isSelected
        self.onSelection = onSelection
    }

    var body: some View {
        AssetSelectionGridCell(
            name: name ?? coin.ticker,
            ticker: coin.ticker,
            logo: coin.logo,
            tokenChainLogo: showChainIcon ? coin.tokenChainLogo : nil,
            isSelected: $isSelected
        ) { onSelection(isSelected) }
        .overlay(alignment: .topTrailing) {
            if verification == .unverified {
                unverifiedBadge
            }
        }
    }

    /// Small warning badge marking a token as unverified (long-tail / unknown
    /// provenance — a scam / impersonation risk). Overlaid on the token tile's
    /// top-trailing corner (mirroring the selected-check's bottom-trailing badge)
    /// and non-interactive so taps pass through to the cell's select button. A
    /// "Unverified" text pill doesn't fit the 74pt-wide grid cell, so the risk is
    /// carried by the icon here and spelled out in the add-confirm copy.
    private var unverifiedBadge: some View {
        Icon(.triangleWarning, color: Theme.colors.alertWarning, size: 12)
            .padding(4)
            .background(Circle().fill(Theme.colors.bgSurface1))
            .overlay(Circle().strokeBorder(Theme.colors.bgPrimary, lineWidth: 2))
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityLabel("tokenUnverifiedBadge".localized)
    }
}

#Preview {
    TokenSelectionGridCell(
        coin: .example,
        verification: .unverified,
        isSelected: false
    ) { _ in }
}
