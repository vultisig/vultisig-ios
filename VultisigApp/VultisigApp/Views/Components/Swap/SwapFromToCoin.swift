//
//  SwapFromToCoin.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapFromToCoin: View {
    let coin: Coin
    
    var body: some View {
        HStack {
            fromToCoinIcon
            fromToCoinContent
            chevron
        }
        .padding(6)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(60)
    }
    
    var fromToCoinIcon: some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 32, height: 32),
            ticker: coin.ticker,
            tokenChainLogo: coin.tokenChainLogo
        )
    }
    
    var fromToCoinContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(coin.ticker)")
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
            
            if coin.isNativeToken {
                Text("Native")
                    .font(Theme.fonts.caption10)
                    .foregroundColor(Theme.colors.textTertiary)
            }
        }
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.caption12)
            .bold()
            .padding(.trailing, 8)
    }
}

#Preview {
    SwapFromToCoin(coin: Coin.example)
}
