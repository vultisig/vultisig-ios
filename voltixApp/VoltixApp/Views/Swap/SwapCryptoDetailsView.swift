//
//  SwapCryptoDetailsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoDetailsView: View {

    @ObservedObject var viewModel: SwapCryptoViewModel

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
            TokenSelectorDropdown(coins: $viewModel.coins, selected: $viewModel.fromCoin)
            getBalance(for: viewModel.fromBalance)
        }
    }
    
    var fromAmountField: some View {
        SendCryptoAmountTextField(amount: $viewModel.fromAmount, onChange: { _ in }, onMaxPressed: { })
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
            TokenSelectorDropdown(coins: $viewModel.coins, selected: $viewModel.toCoin)
            getBalance(for: viewModel.toBalance)
        }
    }
    
    var toAmountField: some View {
        SendCryptoAmountTextField(amount: $viewModel.toAmount, onChange: { _ in }, onMaxPressed: { })
    }
    
    var summary: some View {
        VStack(spacing: 8) {
            getSummaryCell(leadingText: "gas(auto)", trailingText: viewModel.feeString)
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

    private func getBalance(for text: String) -> some View {
        Text("Balance: \(text)")
             .font(.body12Menlo)
             .foregroundColor(.neutral0)
             .frame(maxWidth: .infinity, alignment: .leading)
             .padding(.top, 4)
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
    SwapCryptoDetailsView(viewModel: SwapCryptoViewModel())
}
