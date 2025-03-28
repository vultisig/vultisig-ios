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
    @Binding var selectedChain: Chain?
    @Binding var showNetworkSelectSheet: Bool
    @Binding var showCoinSelectSheet: Bool
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
            fromToChain
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
    
    var fromToChain: some View {
        Button {
            showNetworkSelectSheet = true
        } label: {
            SwapFromToChain(chain: selectedChain)
        }
    }
    
    var fromToCoin: some View {
        Button {
            showCoinSelectSheet = true
        } label: {
            fromToCoinLabel
        }
    }
    
    var fromToCoinLabel: some View {
        SwapFromToCoin(coin: coin)
    }
    
    var fromToAmountField: some View {
        SwapCryptoAmountTextField(amount: $amount) { _ in
            if title=="from" {
                swapViewModel.updateFromAmount(tx: tx, vault: vault)
            }
        }
        .disabled(title=="to")
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
        selectedChain: .constant(Chain.example),
        showNetworkSelectSheet: .constant(false),
        showCoinSelectSheet: .constant(false),
        tx: SwapTransaction(),
        swapViewModel: SwapCryptoViewModel()
    )
}
