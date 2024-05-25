//
//  SwapCryptoDetailsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoDetailsView: View {
    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel

    let vault: Vault

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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                
                Button {
                    hideKeyboard()
                } label: {
                    Text(NSLocalizedString("done", comment: "Done"))
                }
            }
        }
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                fromCoinField
                fromAmountField
                swapButton
                toCoinField
                if swapViewModel.showToAmount(tx: tx) {
                    toAmountField
                }
                summary
            }
            .padding(.horizontal, 16)
        }
    }
    
    var fromCoinField: some View {
        VStack(spacing: 8) {
            getTitle(for: "from")
            TokenSelectorDropdown(coins: $swapViewModel.coins, selected: $tx.fromCoin, onSelect: { _ in
                swapViewModel.updateFromCoin(tx: tx, vault: vault)
            })
            getBalance(for: tx.fromBalance)
                .redacted(reason: tx.fromCoin.balanceDecimal.isZero ? .placeholder : [])
        }
    }
    
    var fromAmountField: some View {
        SendCryptoAmountTextField(amount: $tx.fromAmount, onChange: { _ in
            swapViewModel.updateFromAmount(tx: tx)
        })
    }
    
    var swapButton: some View {
        Button {
            swapViewModel.switchCoins(tx: tx, vault: vault)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.body20MontserratMedium)
                .foregroundColor(.neutral0)
                .frame(width: 50, height: 50)
                .background(Color.persianBlue400)
                .cornerRadius(50)
                .padding(10)
        }
    }
    
    var toCoinField: some View {
        VStack(spacing: 8) {
            getTitle(for: "to")
            TokenSelectorDropdown(coins: $swapViewModel.coins, selected: $tx.toCoin, onSelect: { _ in
                swapViewModel.updateToCoin(tx: tx)
            })
            getBalance(for: tx.toBalance)
                .redacted(reason: tx.toCoin.balanceDecimal.isZero ? .placeholder : [])
        }
    }
    
    var toAmountField: some View {
        SendCryptoAmountTextField(amount: .constant(tx.toAmountDecimal.description), onChange: { _ in })
            .disabled(true)
    }
    
    var summary: some View {
        SwapDetailsSummary(tx: tx, swapViewModel: swapViewModel)
    }
    
    var continueButton: some View {
        Button {
            swapViewModel.moveToNextView()
        } label: {
            FilledButton(title: "continue")
        }
        .disabled(!swapViewModel.validateForm(tx: tx))
        .opacity(swapViewModel.validateForm(tx: tx) ? 1 : 0.5)
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
}

#Preview {
    SwapCryptoDetailsView(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel(), vault: .example)
}
