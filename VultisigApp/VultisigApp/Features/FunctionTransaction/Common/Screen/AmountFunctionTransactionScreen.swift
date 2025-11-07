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
    @Binding var percentageSelected: Int?
    let percentageFieldType: PercentageFieldType
    @StateObject var amountField: FormField
    @Binding var validForm: Bool
    var onVerify: () -> Void
    var customBalanceView: () -> CustomView
    
    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        TransactionFormScreen(
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
                    decimals: coin.decimals,
                    percentage: $percentageSelected,
                    customBalanceView: { customBalanceView() }
                ).focused($focusedField, equals: .amount)
            }
        }
        .onLoad {
            focusedFieldBinding = .amount
        }
        .onChange(of: focusedFieldBinding) { oldValue, newValue in
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
