//
//  StakeTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct StakeTransactionScreen: View {
    enum FocusedField {
        case amount
    }
    
    @StateObject var viewModel: StakeTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void
    
    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    @State var percentageSelected: Int?
    
    var body: some View {
        TransactionFormScreen(
            title: String(format: "stakeCoin".localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: viewModel.amountField.label ?? .empty,
                isValid: viewModel.amountField.valid,
                value: .empty,
                showValue: false,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) { _ in
                focusedFieldBinding = .amount
            } content: {
                AmountTextField(
                    amount: $viewModel.amountField.value,
                    error: $viewModel.amountField.error,
                    ticker: viewModel.coin.ticker,
                    type: .button,
                    availableAmount: viewModel.coin.balanceDecimal,
                    decimals: viewModel.coin.decimals,
                    percentage: $percentageSelected,
                    customView: { autocompoundToggle }
                    
                ).focused($focusedField, equals: .amount)
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .amount
        }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .onChange(of: focusedFieldBinding) { oldValue, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
    }
    
    @ViewBuilder
    var autocompoundToggle: some View {
        if viewModel.supportsAutocompound {
            AutocompoundToggle(isEnabled: $viewModel.isAutocompound)
        }
    }
    
    func onContinue() {
        switch focusedFieldBinding {
        case .amount, nil:
            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            onVerify(transactionBuilder)
        }
    }
}

#Preview {
    StakeTransactionScreen(
        viewModel: StakeTransactionViewModel(
            coin: .example,
            vault: .example
        )
    ) { _ in }
}
