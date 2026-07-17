//
//  InsufficientFeeNotice.swift
//  VultisigApp
//
//  Inline insufficient-fee warning shared by the Cosmos staking input
//  screens (delegate / undelegate / redelegate). Surfaced when the liquid
//  (spendable) balance is below the network fee — the fee is always paid
//  from the liquid balance, so no amount edit can satisfy it and the
//  Continue button is disabled alongside this notice.
//

import SwiftUI

struct InsufficientFeeNotice: View {
    let ticker: String

    var body: some View {
        HStack(spacing: 8) {
            Icon(.circleInfo, color: Theme.colors.alertError, size: 14)
            Text(String(format: "cosmosStakingInsufficientFeeBalance".localized, ticker))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.alertError)
            Spacer()
        }
    }
}
