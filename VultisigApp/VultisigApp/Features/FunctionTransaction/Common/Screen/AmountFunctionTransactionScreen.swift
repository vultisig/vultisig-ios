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
    /// Hard-disables Continue, forwarded to `FormScreen`. For flows with a
    /// pre-flight condition no amount can satisfy — a position that cannot be
    /// withdrawn at all — so the button reads as disabled rather than silently
    /// refusing. Defaults to `false`, leaving every existing caller unchanged.
    let isContinueDisabled: Bool
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
        isContinueDisabled: Bool = false,
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
        self.isContinueDisabled = isContinueDisabled
        self.onVerify = onVerify
        self.customViewPosition = customViewPosition
        self.customView = customView
        self.topView = topView
    }

    var body: some View {
        FormScreen(
            title: title,
            isContinueDisabled: isContinueDisabled,
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
            // Release both halves of the focus before handing off: the
            // `@FocusState` puts the keyboard away, and the intent stops
            // `delayedFocus` handing it straight back. Clearing only the former
            // is why the field comes back highlighted on a layout that was
            // measured without a keyboard.
            //
            // `onVerify` is a `Void` callback and a wrapper may decline to
            // route — an unbuildable transaction, or AddLP's destination
            // refresh landing empty — so this releases focus on those paths
            // too. That is the wrong-way error to make: the form is not
            // advancing, and a keyboard that closes is recoverable with a tap,
            // where a keyboard left over a pushed screen is not.
            focusedFieldBinding = nil
            focusedField = nil
            onVerify()
        }
    }
}
