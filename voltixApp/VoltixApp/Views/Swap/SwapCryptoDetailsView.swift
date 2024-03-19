//
//  SwapCryptoDetailsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoDetailsView: View {
    @ObservedObject var tx: SendTransaction
    let group: GroupedChain
    
    @State var fromAmount = ""
    @State var toAmount = ""
    
    var body: some View {
        ZStack {
            background
            view
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            fields
            continueButton
        }
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                fromCoinField
                fromAmountField
                swapButton
                toCoinField
                toAmountField
                summary
            }
            .padding(.horizontal, 16)
        }
    }
    
    var fromCoinField: some View {
        VStack(spacing: 8) {
            getTitle(for: "from")
//            TokenSelectorDropdown(tx: tx, coinViewModel: <#CoinViewModel#>, group: group)
            
            Text("Balance: 23.2")
                .font(.body12Menlo)
                .foregroundColor(.neutral0)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var fromAmountField: some View {
//        AmountTextField(tx: tx)
        Text("amount")
    }
    
    var swapButton: some View {
        Image(systemName: "arrow.up.arrow.down")
            .font(.body20MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(width: 50, height: 50)
            .background(Color.persianBlue400)
            .cornerRadius(50)
            .padding(10)
    }
    
    var toCoinField: some View {
        VStack(spacing: 8) {
            getTitle(for: "to")
//            TokenSelectorDropdown(tx: tx, group: group)
            
            Text("Balance: 23.2")
                .font(.body12Menlo)
                .foregroundColor(.neutral0)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var toAmountField: some View {
//        AmountTextField(tx: tx)
        Text("Amount")
    }
    
    var summary: some View {
        VStack(spacing: 8) {
            getSummaryCell(leadingText: "amount", trailingText: "0.1 BTC")
            getSummaryCell(leadingText: "gas(auto)", trailingText: "$4.00")
            getSummaryCell(leadingText: "fees", trailingText: "0.001BTC")
            getSummaryCell(leadingText: "time", trailingText: "4 minutes")
        }
    }
    
    var continueButton: some View {
        FilledButton(title: "continue")
            .padding(40)
    }
    
    private func getTitle(for text: String) -> some View {
        Text(NSLocalizedString(text, comment: ""))
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(NSLocalizedString(leadingText, comment: ""))
            Spacer()
            Text(trailingText)
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
    }
}

#Preview {
    SwapCryptoDetailsView(tx: SendTransaction(), group: GroupedChain.example)
}
