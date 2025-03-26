//
//  SwapFromToField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapFromToField: View {
    let title: String
    let vault: Vault
    let coin: Coin
    let fiatAmount: String
    @Binding var amount: String
    @Binding var showNetworkSelectSheet: Bool
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
    }
    
    var header: some View {
        HStack(spacing: 8) {
            fromToLabel
            fromToNetwork
            Spacer()
            balance
        }
    }
    
    var content: some View {
        HStack {
            fromToCoin
            Spacer()
            VStack(spacing: 6) {
                fromToAmountField
                fiatBalance
            }
        }
    }
    
    var fromToLabel: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var fromToNetwork: some View {
        Button {
            showNetworkSelectSheet = true
        } label: {
            fromToNetworkLabel
        }
    }
    
    var fromToNetworkLabel: some View {
        Text("From Network")
    }
    
    var balance: some View {
        Text("\(coin.balanceString) \(coin.ticker)")
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
        .rotationEffect(.degrees(title=="from" ? 0 : 180))
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
        .rotationEffect(.degrees(title=="from" ? 0 : 180))
    }
    
    var fromToCoin: some View {
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
        .frame(width: 36, height: 36)
        .foregroundColor(.black)
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
    
    var fromToAmountField: some View {
        SwapCryptoAmountTextField(amount: $amount) { _ in
            if title=="from" {
                swapViewModel.updateFromAmount(tx: tx, vault: vault)
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
    
    var fiatBalance: some View {
        Text(fiatAmount.formatToFiat(includeCurrencySymbol: true))
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(isFiatVisible() ? 1 : 0)
    }
    
    private func isFiatVisible() -> Bool {
        !amount.isEmpty && amount != "0"
    }
}

#Preview {
    SwapFromToField(
        title: "from",
        vault: Vault.example,
        coin: Coin.example,
        fiatAmount: "0",
        amount: .constant("0"),
        showNetworkSelectSheet: .constant(false),
        tx: SwapTransaction(),
        swapViewModel: SwapCryptoViewModel()
    )
}
