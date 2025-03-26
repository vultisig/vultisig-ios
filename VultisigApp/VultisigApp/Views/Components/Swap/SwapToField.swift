//
//  SwapToField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapToField: View {
    @ObservedObject var tx: SwapTransaction
    
    var body: some View {
        VStack(spacing: 16) {
            header
            content
        }
        .padding(16)
        .background(unevenRectangle)
        .overlay(unevenRectangleBorder)
    }
    
    var header: some View {
        HStack(spacing: 8) {
            toLabel
            toNetwork
            Spacer()
            balance
        }
    }
    
    var content: some View {
        HStack {
            toCoin
            Spacer()
            toAmountField
        }
    }
    
    var toLabel: some View {
        Text(NSLocalizedString("to", comment: ""))
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var toNetwork: some View {
        Text("To Network")
    }
    
    var balance: some View {
        Text("\(tx.toCoin.balanceString) \(tx.toCoin.ticker)")
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var unevenRectangle: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 12,
                bottomLeading: 24,
                bottomTrailing: 24,
                topTrailing: 12
            )
        )
        .foregroundColor(Color.blue600)
    }
    
    var unevenRectangleBorder: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 12,
                bottomLeading: 24,
                bottomTrailing: 24,
                topTrailing: 12
            )
        )
        .stroke(Color.blue400, lineWidth: 1)
    }
    
    var toCoin: some View {
        HStack {
            toCoinIcon
            toCoinContent
            chevron
        }
        .padding(6)
        .background(Color.blue400)
        .cornerRadius(60)
    }
    
    var toCoinIcon: some View {
        AsyncImageView(
            logo: tx.toCoin.logo,
            size: CGSize(width: 32, height: 32),
            ticker: tx.toCoin.ticker,
            tokenChainLogo: tx.toCoin.chain.logo
        )
        .frame(width: 36, height: 36)
        .foregroundColor(.black)
    }
    
    var toCoinContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(tx.toCoin.ticker)")
                .font(.body12BrockmannMedium)
                .foregroundColor(.neutral0)
            
            if tx.toCoin.isNativeToken {
                Text("Native")
                    .font(.body10BrockmannMedium)
                    .foregroundColor(.extraLightGray)
            }
        }
    }
    
    var toAmountField: some View {
        SwapCryptoAmountTextField(
            amount: .constant(tx.toAmountDecimal.description),
            onChange: { _ in }
        )
        .disabled(true)
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
    SwapToField(tx: SwapTransaction())
}
