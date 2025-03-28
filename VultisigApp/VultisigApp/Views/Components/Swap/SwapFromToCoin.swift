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
        .background(Color.blue400)
        .cornerRadius(60)
    }
    
    var fromToCoinIcon: some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 36, height: 36),
            ticker: coin.ticker,
            tokenChainLogo: coin.chain.logo
        )
    }
    
    var fromToCoinContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(coin.ticker)")
                .font(.body12BrockmannMedium)
                .foregroundColor(.neutral0)
            
            if coin.isNativeToken {
                Text("Native")
                    .font(.body10BrockmannMedium)
                    .foregroundColor(.extraLightGray)
            }
        }
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(.neutral0)
            .font(.body12BrockmannMedium)
            .bold()
            .padding(.trailing, 8)
    }
}

#Preview {
    SwapFromToCoin(coin: Coin.example)
}
