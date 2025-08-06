//
//  SwapCoinCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-27.
//

import SwiftUI

struct SwapCoinCell: View {
    let coin: CoinMeta
    let balance: String?
    let balanceFiat: String?
    let isSelected: Bool
    
    var onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            label
        }
    }
    
    var label: some View {
        VStack(spacing: 0) {
            content
            GradientListSeparator()
        }
        .background(isSelected ? Color.blue400 : Color.blue600)
    }
    
    var content: some View {
        HStack {
            icon
            title
            chain
            Spacer()
            
            if isSelected {
                check
            } else {
                balanceView
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
    
    var icon: some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 32, height: 32),
            ticker: coin.ticker,
            tokenChainLogo: coin.chain.logo
        )
    }
    
    var title: some View {
        Text(coin.ticker)
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var chain: some View {
        Text(coin.chain.name)
            .foregroundColor(.lightText)
            .font(.body10BrockmannMedium)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.blue400, lineWidth: 1)
            )
    }
    
    var check: some View {
        Image(systemName: "checkmark")
            .font(.body12BrockmannMedium)
            .foregroundColor(.alertTurquoise)
            .frame(width: 24, height: 24)
            .background(Color.blue600)
            .cornerRadius(32)
            .bold()
    }
    
    @ViewBuilder
    var balanceView: some View {
        if let balance, let balanceFiat {
            VStack(alignment: .trailing, spacing: 4) {
                Text(balance)
                    .foregroundColor(.neutral0)
                
                Text(balanceFiat)
                    .foregroundColor(.extraLightGray)
            }
            .font(.body12BrockmannMedium)
        }
    }
}

#Preview {
    SwapCoinCell(
        coin: CoinMeta.example,
        balance: "1000",
        balanceFiat: "10",
        isSelected: true,
        onSelect: {}
    )
}
