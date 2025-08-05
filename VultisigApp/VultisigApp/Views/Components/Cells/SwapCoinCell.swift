//
//  SwapCoinCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-27.
//

import SwiftUI

struct SwapCoinCell: View {
    let coin: Coin
    @Binding var selectedCoin: Coin
    @Binding var showSheet: Bool
    
    @State var isSelected = false
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            label
        }
        .onAppear {
            setData()
        }
    }
    
    var label: some View {
        VStack(spacing: 0) {
            content
            Separator()
                .opacity(0.2)
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
                balance
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
            .foregroundColor(.lightText)
            .font(Theme.fonts.caption10)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.blue400, lineWidth: 1)
            )
    }
    
    var check: some View {
        Image(systemName: "checkmark")
            .font(Theme.fonts.caption12)
            .foregroundColor(.alertTurquoise)
            .frame(width: 24, height: 24)
            .background(Color.blue600)
            .cornerRadius(32)
            .bold()
    }
    
    var balance: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(coin.balanceString)
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(coin.balanceInFiat)
                .foregroundColor(.extraLightGray)
        }
        .font(Theme.fonts.caption12)
    }
    
    private func setData() {
        isSelected = coin == selectedCoin
    }
    
    private func handleTap() {
        selectedCoin = coin
        showSheet = false
    }
}

#Preview {
    SwapCoinCell(
        coin: Coin.example,
        selectedCoin: .constant(Coin.example),
        showSheet: .constant(true)
    )
}
