//
//  CoinAmountFiatLabel.swift
//  VultisigApp
//

import SwiftUI

/// Amount + ticker with an optional fiat sub-line, in the swap verify asset
/// cell's typography and layout (`bodyLMedium` amount, `caption12` fiat —
/// see `SwapVerifyScreen.getSwapAssetCell`). Shared by the send verify
/// surfaces (initiator + co-sign, hero and non-hero headers) so amounts
/// render with the same UX as the swap screens and the surfaces can't drift.
struct CoinAmountFiatLabel: View {
    let amount: String
    let ticker: String
    let fiat: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                Text(amount)
                    .foregroundStyle(Theme.colors.textPrimary) +
                Text(" ") +
                Text(ticker)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .font(Theme.fonts.bodyLMedium)

            if let fiat, !fiat.isEmpty {
                Text(fiat)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }
}
