//
//  AmountFunctionTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/11/2025.
//

import SwiftUI

struct AmountFunctionTransactionScreen<CustomView: View>: View {
    enum FocusedField {
        case amount
    }

    let title: String
    let coin: CoinMeta
    let availableAmount: Decimal
    @Binding var percentageSelected: Double?
    let percentageFieldType: PercentageFieldType
    @StateObject var amountField: FormField
    @Binding var validForm: Bool
    var onVerify: () -> Void
    var customViewPosition: AmountTextField<CustomView>.CustomViewPosition
    var customView: () -> CustomView

    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?

    init(
        title: String,
        coin: CoinMeta,
        availableAmount: Decimal,
        percentageSelected: Binding<Double?>,
        percentageFieldType: PercentageFieldType,
        amountField: FormField,
        validForm: Binding<Bool>,
        customViewPosition: AmountTextField<CustomView>.CustomViewPosition = .balance,
        onVerify: @escaping () -> Void,
        @ViewBuilder customView: @escaping () -> CustomView
    ) {
        self.title = title
        self.coin = coin
        self.availableAmount = availableAmount
        self._percentageSelected = percentageSelected
        self.percentageFieldType = percentageFieldType
        self._amountField = StateObject(wrappedValue: amountField)
        self._validForm = validForm
        self.onVerify = onVerify
        self.customViewPosition = customViewPosition
        self.customView = customView
    }

    var body: some View {
        FormScreen(
            title: title,
            validForm: $validForm,
            onContinue: onContinue
        ) {
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
                    decimals: 4, // keep 4 decimals
                    percentage: $percentageSelected,
                    customViewPosition: customViewPosition,
                    customView: { customView() }
                ).focused($focusedField, equals: .amount)
            }
        }
        .onLoad {
            focusedFieldBinding = .amount
        }
        .onChange(of: focusedFieldBinding) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
    }

    func onContinue() {
        switch focusedFieldBinding {
        case .amount, nil:
            onVerify()
        }
    }
}
