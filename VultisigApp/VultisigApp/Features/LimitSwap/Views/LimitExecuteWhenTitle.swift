//
//  LimitExecuteWhenTitle.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Execute When card title
//
// "When 1 [icon] <TICKER> is worth" — the icon + ticker reference the source
// asset (the thing being sold) and are tappable as a single chip that opens the
// from-asset picker.

struct LimitExecuteWhenTitle: View {

    let asset: LimitSwapAsset
    let onTapAsset: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("limitSwap.executeWhen.headerWhenOne".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            LimitAssetChip(
                asset: asset,
                iconSize: 16,
                action: onTapAsset
            )

            Text("limitSwap.executeWhen.headerIsWorth".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .lineLimit(1)
    }
}
