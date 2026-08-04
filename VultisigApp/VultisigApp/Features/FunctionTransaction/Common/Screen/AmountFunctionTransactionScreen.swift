//
//  AmountFunctionTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/11/2025.
//

import SwiftUI

struct AmountFunctionTransactionScreen<CustomView: View, TopView: View>: View {
    enum FocusedField {
        case amount
    }

    let title: String
    let coin: CoinMeta
    let availableAmount: Decimal
    @Binding var percentageSelected: Double?
    let percentageFieldType: PercentageFieldType
    /// Precision the percentage buttons write into the field.
    ///
    /// Four is right for a display-oriented form, but a percentage button
    /// truncates to it, so on a nine-decimal asset a "100%" that means the
    /// measured maximum would silently leave the last five decimals behind.
    /// Callers whose maximum is exact pass the asset's own scale.
    let amountDecimals: Int
    @StateObject var amountField: FormField
    @Binding var validForm: Bool
    var onVerify: () -> Void
    var customViewPosition: AmountTextField<CustomView>.CustomViewPosition
    var customView: () -> CustomView
    var topView: () -> TopView

    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?

    init(
        title: String,
        coin: CoinMeta,
        availableAmount: Decimal,
        percentageSelected: Binding<Double?>,
        percentageFieldType: PercentageFieldType,
        amountDecimals: Int = 4,
        amountField: FormField,
        validForm: Binding<Bool>,
        customViewPosition: AmountTextField<CustomView>.CustomViewPosition = .balance,
        onVerify: @escaping () -> Void,
        @ViewBuilder customView: @escaping () -> CustomView,
        @ViewBuilder topView: @escaping () -> TopView = { EmptyView() }
    ) {
        self.title = title
        self.coin = coin
        self.availableAmount = availableAmount
        self._percentageSelected = percentageSelected
        self.percentageFieldType = percentageFieldType
        self.amountDecimals = amountDecimals
        self._amountField = StateObject(wrappedValue: amountField)
        self._validForm = validForm
        self.onVerify = onVerify
        self.customViewPosition = customViewPosition
        self.customView = customView
        self.topView = topView
    }

    var body: some View {
        FormScreen(
            title: title,
            validForm: $validForm,
            onContinue: onContinue
        ) {
            topView()
            FormExpandableSection(
                title: amountField.label ?? .empty,
                isValid: amountField.valid,
                value: .empty,
                showValue: false,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) { _ in
                focusedFieldBinding = .amount
            } content: {
                AmountTextField(
                    amount: $amountField.value,
                    error: $amountField.error,
                    ticker: coin.ticker,
                    type: percentageFieldType,
                    availableAmount: availableAmount,
                    decimals: amountDecimals,
                    percentage: $percentageSelected,
                    customViewPosition: customViewPosition,
                    customView: { customView() }
                ).focused($focusedField, equals: .amount)
            }
        }
        .onLoad {
            focusedFieldBinding = .amount
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
    }

    func onContinue() {
        switch focusedFieldBinding {
        case .amount, nil:
            onVerify()
        }
    }
}
