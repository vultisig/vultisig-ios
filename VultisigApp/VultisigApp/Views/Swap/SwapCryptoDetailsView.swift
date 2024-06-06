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
    
    @State var buttonRotated = false
    @State var toCoins = [Coin]()

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
            VStack(spacing: 8) {
                fromCoinField
                swapContent
                toCoinField
                summary
            }
            .padding(.horizontal, 16)
        }
    }
    
    var swapContent: some View {
        ZStack {
            content
            swapButton
        }
    }
    
    var content: some View {
        VStack(spacing: 8) {
            fromAmountField
            toAmountField
        }
    }
    
    var fromCoinField: some View {
        VStack(spacing: 8) {
            TokenSelectorDropdown(
                coins: $swapViewModel.coins,
                selected: $tx.fromCoin,
                onSelect: { _ in
                    swapViewModel.updateFromCoin(tx: tx, vault: vault)
                }
            )
        }
    }
    
    var fromAmountField: some View {
        SwapCryptoAmountTextField(
            title: "from",
            fiatAmount: swapViewModel.fromFiatAmount(tx: tx),
            amount: $tx.fromAmount
        ) { _ in
            swapViewModel.updateFromAmount(tx: tx, vault: vault)
        }
    }
    
    var swapButton: some View {
        Button {
            buttonRotated.toggle()
            swapViewModel.switchCoins(tx: tx, vault: vault)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.body16MontserratMedium)
                .foregroundColor(.neutral0)
                .frame(width: 38, height: 38)
                .background(Color.persianBlue400)
                .cornerRadius(50)
                .padding(2)
                .background(Color.black.opacity(0.2))
                .cornerRadius(50)
                .rotationEffect(.degrees(buttonRotated ? 180 : 0))
                .animation(.spring, value: buttonRotated)
        }
    }
    
    var toCoinField: some View {
        VStack(spacing: 8) {
            TokenSelectorDropdown(
                coins: $toCoins,
                selected: $tx.toCoin,
                onSelect: { _ in
                    swapViewModel.updateToCoin(tx: tx, vault: vault)
                }
            )
        }
        .onChange(of: tx.fromCoin) { oldValue, newValue in
            setData()
        }
    }
    
    var toAmountField: some View {
        SwapCryptoAmountTextField(
            title: "to",
            fiatAmount: swapViewModel.toFiatAmount(tx: tx),
            amount: .constant(tx.toAmountDecimal.description),
            onChange: { _ in }
        )
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
    
    private func setData() {
        toCoins = swapViewModel.coins.filter({ coin in
            coin.id != tx.fromCoin.id
        })
        
        if let firstCoin = toCoins.first {
            tx.toCoin = firstCoin
        }
    }
}

#Preview {
    SwapCryptoDetailsView(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel(), vault: .example)
}
