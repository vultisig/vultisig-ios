//
//  SendDetailsAmountTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-02.
//

import SwiftUI

struct SendDetailsAmountTextField: View {
    @Bindable var viewModel: SendDetailsViewModel
    @FocusState.Binding var focusedField: Field?

    @State var isCryptoSelected: Bool = true

    var body: some View {
        HStack {
            inFocusSelector.opacity(0)
            textFieldSection
            inFocusSelector
        }
        .frame(idealHeight: 100, maxHeight: 180)
        .animation(.easeInOut, value: isCryptoSelected)
        .onChange(of: focusedField) { _, newValue in
            if newValue == .amount {
                isCryptoSelected = true
            } else if newValue == .amountInFiat {
                isCryptoSelected = false
            }
        }
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
        .background(Theme.colors.bgSurface1)
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
            if focusedField == .amountInFiat {
                focusedField = .amount
            }
        } label: {
            getSelector(for: "circle.dotted.and.circle")
        }
    }

    var fiatSelector: some View {
        Button {
            isCryptoSelected = false
            if focusedField == .amount {
                focusedField = .amountInFiat
            }
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
            amount: $viewModel.amount,
            onChange: { viewModel.convertToFiat(newValue: $0) },
            onMaxPressed: { Task { await viewModel.setMaxAmount() } }
        )
        .focused($focusedField, equals: .amount)
        .onChange(of: viewModel.coin) { _, _ in
            viewModel.convertToFiat(newValue: viewModel.amount)
        }
    }

    var amountUnitField: some View {
        getUnit(for: viewModel.coin.ticker)
    }

    var amountFiatDescription: some View {
        getDescriptionText(for: viewModel.amountInFiat.formatToFiat())
            .redacted(reason: viewModel.amountInFiat.isEmpty ? .placeholder : [])
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
            amount: $viewModel.amountInFiat,
            onChange: { viewModel.convertFiatToCoin(newValue: $0) }
        )
        .focused($focusedField, equals: .amountInFiat)
    }

    var fiatUnitField: some View {
        getUnit(for: SettingsCurrency.current.rawValue)
    }

    var fiatAmountDescription: some View {
        getDescriptionText(for: viewModel.amount.formatToDecimal(digits: 8) + " " + viewModel.coin.ticker)
            .redacted(reason: viewModel.amount.isEmpty ? .placeholder : [])
    }

    private func getUnit(for unit: String) -> some View {
        Text(unit)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }

    private func getDescriptionText(for value: String) -> some View {
        Text(value)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textTertiary)
            .padding(.top, 8)
    }

    private func getSelector(for icon: String) -> some View {
        Image(systemName: icon)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(width: 32, height: 32)
    }
}
