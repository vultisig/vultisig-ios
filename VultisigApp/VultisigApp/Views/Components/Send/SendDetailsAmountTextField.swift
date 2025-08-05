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
            amountSection
                .opacity(isCryptoSelected ? 1 : 0)
            fiatSection
                .opacity(isCryptoSelected ? 0 : 1)
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
        .background(Theme.colors.bgSecondary)
        .cornerRadius(32)
    }
    
    var selectorOvelay: some View {
        Circle()
            .frame(width: 32, height: 32)
            .foregroundColor(Theme.colors.bgButtonTertiary)
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
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    private func getDescriptionText(for value: String) -> some View {
        Text(value)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textExtraLight)
            .padding(.top, 8)
    }
    
    private func getSelector(for icon: String) -> some View {
        Image(systemName: icon)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(width: 32, height: 32)
    }
}

#Preview {
    SendDetailsAmountTextField(tx: SendTransaction(), viewModel: SendDetailsViewModel(), sendCryptoViewModel: SendCryptoViewModel())
}
