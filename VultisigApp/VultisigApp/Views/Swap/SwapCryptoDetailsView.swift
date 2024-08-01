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
    @State var isFromPickerActive = false
    @State var isToPickerActive = false

    let vault: Vault

    var body: some View {
        ZStack {
            Background()
            view

            if swapViewModel.isLoading {
                Loader()
            }
        }
        .navigationDestination(isPresented: $isFromPickerActive) {
            CoinPickerView(coins: tx.fromCoins) { coin in
                swapViewModel.updateFromCoin(coin: coin, tx: tx, vault: vault)
                swapViewModel.updateCoinLists(tx: tx)
            }
        }
        .navigationDestination(isPresented: $isToPickerActive) {
            CoinPickerView(coins: tx.toCoins) { coin in
                swapViewModel.updateToCoin(coin: coin, tx: tx, vault: vault)
            }
        }
    }
    
    var view: some View {
        VStack {
            fields
            continueButton
        }
#if os(iOS)
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
#elseif os(macOS)
        .padding(.horizontal, 25)
#endif
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
                coin: tx.fromCoin,
                onPress: {
                    isFromPickerActive = true
                }
            )
            .redacted(reason: tx.fromCoin == .example ? .placeholder : [])
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
            swapViewModel.updateCoinLists(tx: tx)
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
                coin: tx.toCoin,
                onPress: {
                    isToPickerActive = true
                }
            )
            .redacted(reason: tx.toCoin == .example ? .placeholder : [])
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
            Task {
                swapViewModel.moveToNextView()
            }
        } label: {
            FilledButton(title: "continue")
        }
        .disabled(!swapViewModel.validateForm(tx: tx))
        .opacity(swapViewModel.validateForm(tx: tx) ? 1 : 0.5)
        .padding(40)
    }
}

#Preview {
    SwapCryptoDetailsView(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel(), vault: .example)
}
