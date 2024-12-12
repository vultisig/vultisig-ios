//
//  CoinPickerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-11.
//

import SwiftUI

struct CoinPickerCell: View {
    let coin: Coin
    
    var body: some View {
        content
    }
    
    var content: some View {
        HStack(spacing: 16) {
            AsyncImageView(
                logo: coin.logo,
                size: CGSize(width: 32, height: 32),
                ticker: coin.ticker,
                tokenChainLogo: coin.chain.logo
            )
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(coin.chain.name)
                    Spacer()
                    Text(coin.balanceString)
                        .font(.body12MenloBold)
                    
                    Text(coin.balanceInFiat)
                }
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)

                Text(coin.address)
                    .font(.body12MenloBold)
                    .foregroundColor(.turquoise400)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
    }
}

#Preview {
    CoinPickerCell(coin: Coin.example)
}
