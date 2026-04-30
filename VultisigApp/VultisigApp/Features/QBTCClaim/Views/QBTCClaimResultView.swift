//
//  QBTCClaimResultView.swift
//  VultisigApp
//
//  Success screen — locally-computed tx hash + "View on explorer"
//  link. The hash matches the SDK + windows (uppercase SHA-256 of
//  the TxRaw — does NOT come from the broadcast response).
//

import SwiftUI

struct QBTCClaimResultView: View {
    let result: QBTCClaimRunResult
    let qbtcCoin: Coin?
    /// `nil` when the chain has no public explorer wired up — the CTA is hidden.
    let explorerURL: URL?
    let onOpenExplorer: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.colors.alertSuccess)
            Text("qbtcClaimSuccessTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(QBTCClaimAmountFormatter.formatBtc(sats: result.totalSatsClaimed))
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("qbtcClaimSuccessDetail".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                Text("qbtcClaimTxHashLabel".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(result.txHashHex)
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(8)

            if let explorerURL {
                PrimaryButton(title: "qbtcClaimViewOnExplorer".localized) {
                    onOpenExplorer(explorerURL)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
