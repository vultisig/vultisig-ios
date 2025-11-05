//
//  UnstakeTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct UnstakeTransactionScreen: View {
    enum FocusedField {
        case amount
    }
    
    @StateObject var viewModel: UnstakeTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void
    
    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        TransactionFormScreen(
            title: String(format: "unstakeCoin".localized, viewModel.coin.ticker),
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
                    type: .slider,
                    availableAmount: viewModel.availableAmount,
                    decimals: viewModel.coin.decimals,
                    percentage: $viewModel.percentageSelected,
                    customView: { autocompoundToggle }
                ).focused($focusedField, equals: .amount)
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .amount
        }
        .onChange(of: viewModel.percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
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
            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            onVerify(transactionBuilder)
        }
    }
    
    @ViewBuilder
    var autocompoundToggle: some View {
        if viewModel.supportsAutocompound {
            AutocompoundToggle(isEnabled: $viewModel.isAutocompound)
        }
    }
}

struct AutocompoundToggle: View {
    @Binding var isEnabled: Bool
    var body: some View {
        HStack {
            Text("enableAutoCompounding".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            Toggle("", isOn: $isEnabled)
                .scaleEffect(0.8)
                .tint(Theme.colors.primaryAccent4)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

#Preview {
    UnstakeTransactionScreen(
        viewModel: UnstakeTransactionViewModel(
            coin: .example,
            vault: .example
        )
    ) { _ in }
}
