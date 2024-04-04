//
//  SwapCryptoDetailsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoDetailsView: View {
   
    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel
    @ObservedObject var coinViewModel: CoinViewModel

    let group: GroupedChain
    
    @State var fromAmount = ""
    @State var toAmount = ""
    @State var isToCoinExpanded = false

    var body: some View {
        ZStack {
            Background()
            view
        }
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
            TokenSelectorDropdown(coinViewModel: coinViewModel, group: group, selected: tx.fromCoin)
        }
    }
    
    var fromAmountField: some View {
        SendCryptoAmountTextField(amount: $tx.fromAmount, onChange: { _ in }, onMaxPressed: { })
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
            TokenSelectorDropdown(coinViewModel: coinViewModel, group: group, selected: tx.toCoin, isActive: true, isExpanded: isToCoinExpanded)
        }
    }
    
    var toAmountField: some View {
        SendCryptoAmountTextField(amount: $tx.fromAmount, onChange: { _ in }, onMaxPressed: { })
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
    SwapCryptoDetailsView(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel(), coinViewModel: CoinViewModel(), group: GroupedChain.example)
}
