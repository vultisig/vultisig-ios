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
        .background(isSelected ? Theme.colors.bgTertiary : Theme.colors.bgSecondary)
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
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var chain: some View {
        Text(coin.chain.name)
            .foregroundColor(Theme.colors.textLight)
            .font(Theme.fonts.caption10)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.bgTertiary, lineWidth: 1)
            )
    }
    
    var check: some View {
        Image(systemName: "checkmark")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.alertInfo)
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(32)
            .bold()
    }
    
    @ViewBuilder
    var balanceView: some View {
        if let balance, let balanceFiat {
            VStack(alignment: .trailing, spacing: 4) {
                Text(balance)
                    .foregroundColor(Theme.colors.textPrimary)
                
                Text(balanceFiat)
                    .foregroundColor(Theme.colors.textExtraLight)
            }
            .font(Theme.fonts.caption12)
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
