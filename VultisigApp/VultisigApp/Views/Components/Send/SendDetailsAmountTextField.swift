//
//  SendDetailsAmountTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-02.
//

import SwiftUI

struct SendDetailsAmountTextField: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    
    @State var isCryptoSelected: Bool = true
    
    var body: some View {
        HStack {
            inFocusSelector.opacity(0)
            textFieldSection
            inFocusSelector
        }
        .frame(height: 180)
        .animation(.easeInOut, value: isCryptoSelected)
    }
    
    var textFieldSection: some View {
        ZStack {
            if isCryptoSelected {
                amountSection
            } else {
                fiatSection
            }
        }
    }
    
    var inFocusSelector: some View {
        ZStack {
            selectorOvelay
            
            VStack(spacing: 2) {
                cryptoSelector
                fiatSelector
            }
        }
        .padding(3)
        .background(Color.blue600)
        .cornerRadius(32)
    }
    
    var selectorOvelay: some View {
        Circle()
            .frame(width: 32, height: 32)
            .foregroundColor(.persianBlue400)
            .offset(y: isCryptoSelected ? -16 : 16)
    }
    
    var cryptoSelector: some View {
        Button {
            isCryptoSelected = true
        } label: {
            getSelector(for: "circle.dotted.and.circle")
        }
    }
    
    var fiatSelector: some View {
        Button {
            isCryptoSelected = false
        } label: {
            getSelector(for: "dollarsign")
        }
    }
    
    // Crypto
    var amountSection: some View {
        VStack(spacing: 2) {
            amountField
            amountUnitField
            amountFiatDescription
        }
    }
    
    var amountField: some View {
        SendCryptoAmountTextField(
            amount: $tx.amount,
            onChange: {
                sendCryptoViewModel.convertToFiat(newValue: $0, tx: tx)
            },
            onMaxPressed: { sendCryptoViewModel.setMaxValues(tx: tx) }
        )
        .onChange(of: tx.coin) { oldValue, newValue in
            sendCryptoViewModel.convertToFiat(newValue: tx.amount, tx: tx)
        }
    }
    
    var amountUnitField: some View {
        getUnit(for: tx.coin.ticker)
    }
    
    var amountFiatDescription: some View {
        getDescriptionText(for: tx.amountInFiat.formatToFiat())
            .redacted(reason: tx.amountInFiat.isEmpty ? .placeholder : [])
    }
    
    // Fiat
    var fiatSection: some View {
        VStack(spacing: 6) {
            textFiatField
            fiatUnitField
            fiatAmountDescription
        }
    }
    
    var textFiatField: some View {
        SendCryptoAmountTextField(
            amount: $tx.amountInFiat,
            onChange: { sendCryptoViewModel.convertFiatToCoin(newValue: $0, tx: tx) }
        )
    }
    
    var fiatUnitField: some View {
        getUnit(for: SettingsCurrency.current.rawValue)
    }
    
    var fiatAmountDescription: some View {
        getDescriptionText(for: tx.amount.formatToDecimal(digits: 8) + " " + tx.coin.ticker)
            .redacted(reason: tx.amount.isEmpty ? .placeholder : [])
    }
    
    private func getUnit(for unit: String) -> some View {
        Text(unit)
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    private func getDescriptionText(for value: String) -> some View {
        Text(value)
            .font(.body14BrockmannMedium)
            .foregroundColor(.extraLightGray)
            .padding(.top, 8)
    }
    
    private func getSelector(for icon: String) -> some View {
        Image(systemName: icon)
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
            .frame(width: 32, height: 32)
    }
}

#Preview {
    SendDetailsAmountTextField(tx: SendTransaction(), viewModel: SendDetailsViewModel(), sendCryptoViewModel: SendCryptoViewModel())
}
