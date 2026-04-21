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
    let heroTitle: String?
    let heroAmount: String?
    let heroTicker: String?
    let heroImage: String?
    let heroCaption: String?
    let status: TransactionStatus

    var body: some View {
        VStack(spacing: 36) {
            TransactionStatusHeaderView(status: status)
                .frame(minHeight: 150, maxHeight: 200)

            VStack(spacing: 8) {
                Text(heroTitle ?? "")
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .showIf(heroTitle != nil)

                if let heroCaption {
                    Text(heroCaption)
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if let heroAmount, let heroTicker {
                    VStack(spacing: 12) {
                        if let heroImage, !heroImage.isEmpty {
                            AsyncImageView(
                                logo: heroImage,
                                size: CGSize(width: 36, height: 36),
                                ticker: heroTicker,
                                tokenChainLogo: nil
                            )
                        }

                        (
                            Text(heroAmount)
                                .foregroundStyle(Theme.colors.textPrimary) +
                            Text(" \(heroTicker)")
                                .foregroundStyle(Theme.colors.textTertiary)
                        )
                        .font(Theme.fonts.bodyLMedium)
                    }
                } else if heroTitle == nil {
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
