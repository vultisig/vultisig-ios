//
//  SendCryptoDoneHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/08/2025.
//

import SwiftUI

struct SendCryptoDoneHeaderView: View {
    let coin: Coin?
    let cryptoAmount: String
    let fiatAmount: String
    let status: TransactionStatus

    var body: some View {
        VStack {
            TransactionStatusHeaderView(status: status)

            VStack(spacing: 8) {
                if let coin {
                    AsyncImageView(
                        logo: coin.logo,
                        size: CGSize(width: 32, height: 32),
                        ticker: coin.ticker,
                        tokenChainLogo: coin.tokenChainLogo
                    )
                }

                VStack(spacing: 4) {
                    Text(cryptoAmount)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(fiatAmount)
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.colors.bgSurface2, lineWidth: 1)
            )
        }
    }
}
