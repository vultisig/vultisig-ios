//
//  CoinAmountFiatLabel.swift
//  VultisigApp
//

import SwiftUI

/// Amount + ticker with an optional fiat sub-line (`bodyLMedium` amount,
/// `caption12` fiat). Shared by the send summary surfaces (co-sign, hero and
/// non-hero headers) so amounts render with the same UX and the surfaces
/// can't drift.
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
