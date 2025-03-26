//
//  SwapFromField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapFromField: View {
    let vault: Vault
    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            header
            content
        }
        .padding(16)
        .background(unevenRectangle)
        .overlay(unevenRectangleBorder)
        .padding(.horizontal, 16)
    }
    
    var header: some View {
        HStack(spacing: 8) {
            fromLabel
            fromNetwork
            Spacer()
            balance
        }
    }
    
    var content: some View {
        HStack {
            fromCoin
            Spacer()
            fromAmountField
        }
    }
    
    var fromLabel: some View {
        Text(NSLocalizedString("from", comment: ""))
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var fromNetwork: some View {
        Text("From Network")
    }
    
    var balance: some View {
        Text("\(tx.fromCoin.balanceString) \(tx.fromCoin.ticker)")
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var unevenRectangle: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 24,
                bottomLeading: 12,
                bottomTrailing: 12,
                topTrailing: 24
            )
        )
        .foregroundColor(Color.blue600)
    }
    
    var unevenRectangleBorder: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 24,
                bottomLeading: 12,
                bottomTrailing: 12,
                topTrailing: 24
            )
        )
        .stroke(Color.blue400, lineWidth: 1)
    }
    
    var fromCoin: some View {
        HStack {
            fromCoinIcon
            fromCoinContent
            chevron
        }
        .padding(6)
        .background(Color.blue400)
        .cornerRadius(60)
    }
    
    var fromCoinIcon: some View {
        AsyncImageView(
            logo: tx.fromCoin.logo,
            size: CGSize(width: 32, height: 32),
            ticker: tx.fromCoin.ticker,
            tokenChainLogo: tx.fromCoin.chain.logo
        )
        .frame(width: 36, height: 36)
        .foregroundColor(.black)
    }
    
    var fromCoinContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(tx.fromCoin.ticker)")
                .font(.body12BrockmannMedium)
                .foregroundColor(.neutral0)
            
            if tx.fromCoin.isNativeToken {
                Text("Native")
                    .font(.body10BrockmannMedium)
                    .foregroundColor(.extraLightGray)
            }
        }
    }
    
    var fromAmountField: some View {
        SwapCryptoAmountTextField(amount: $tx.fromAmount) { _ in
            swapViewModel.updateFromAmount(tx: tx, vault: vault)
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
    SwapFromField(
        vault: Vault.example,
        tx: SwapTransaction(),
        swapViewModel: SwapCryptoViewModel()
    )
}
