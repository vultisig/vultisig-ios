//
//  TokenSelectorDropdown.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct TokenSelectorDropdown: View {
    let coin: Coin
    let balance: String? = nil
    let onPress: (() -> Void)?

    var body: some View {
        cell
            .onTapGesture {
                onPress?()
            }
    }
    
    var cell: some View {
        HStack(spacing: 10) {
            image
            ticker
            Spacer()
            balanceContent
            arrow
        }
        .redacted(reason: coin.balanceString.isEmpty ? .placeholder : [])
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var image: some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 32, height: 32),
            ticker: coin.ticker,
            tokenChainLogo: coin.chain.logo
        )
    }
    
    var ticker: some View {
        Text("\(coin.ticker)")
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
    }

    var arrow: some View {
        Image("arrow")
            .frame(width: 20, height: 20)
    }

    var balanceContent: some View {
        HStack(spacing: 0) {
            Group {
                Text(NSLocalizedString("balance", comment: "")) +
                Text(": ")
            }
            
            if let balance {
                Text(balance)
            } else {
                Text(coin.balanceString.formatCurrencyAbbreviation())
            }
        }
        .font(.body12MenloBold)
        .foregroundColor(.neutral200)
    }
    
    private func getCell(for coin: Coin) -> some View {
        HStack(spacing: 12) {
            AsyncImageView(logo: coin.logo, size: CGSize(width: 32, height: 32), ticker: coin.ticker, tokenChainLogo: coin.tokenChainLogo)
            
            Text(coin.ticker)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)

            if let schema = coin.tokenSchema {
                Text("(\(schema))")
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
            }

            Spacer()
        }
        .frame(height: 48)
    }
}

#Preview {
    ZStack {
        Background()
        TokenSelectorDropdown(coin: .example, onPress: nil)
    }
}
