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
    
    var body: some View {
        VStack(spacing: 8) {
            Text("sent".localized)
                .foregroundStyle(Theme.colors.textExtraLight)
                .font(Theme.fonts.caption10)
            
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
                    .foregroundColor(Theme.colors.textPrimary)
                Text(fiatAmount)
                    .font(Theme.fonts.caption10)
                    .foregroundColor(Theme.colors.textExtraLight)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.bgTertiary, lineWidth: 1)
        )
    }
}
