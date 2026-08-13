//
//  LimitAssetChip.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Tappable asset chip
//
// The shared construction behind BOTH asset-picker chips in the price card (the
// "When 1 [chip] is worth" source chip and the trailing target chip), so the two
// stay symmetric with each other. Matches the established asset-pill style used by
// `LimitAssetRow` — filled `bgSurface2` capsule with the 6/12/6 padding — so the
// fill (not just a border) is what signals "tappable". The ticker takes the same
// `caption12` the Sell/Buy coin pills use, so every asset chip on the screen
// speaks one type size; only the icon scales with the row it sits in.

struct LimitAssetChip: View {

    let asset: LimitSwapAsset
    let iconSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !asset.logo.isEmpty {
                    AsyncImageView(
                        logo: asset.logo,
                        size: CGSize(width: iconSize, height: iconSize),
                        ticker: asset.ticker,
                        // No chain badge on a native asset — its icon already IS
                        // the chain, so the badge repeats it. `LimitAssetRow`
                        // has always done this; the chips did not, so RUNE and
                        // ETH carried a redundant dot in the price card while
                        // the same assets were clean in the Sell/Buy rows.
                        tokenChainLogo: asset.isNativeToken ? nil : asset.chainLogo
                    )
                }
                Text(asset.ticker)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Theme.colors.bgSurface2)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
