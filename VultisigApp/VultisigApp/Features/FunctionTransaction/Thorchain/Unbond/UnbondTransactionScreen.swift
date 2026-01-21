//
//  UnbondTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct UnbondTransactionScreen: View {
    enum FocusedField {
        case address, amount
    }

    @StateObject var viewModel: UnbondTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    @State var percentageSelected: Double?

    var body: some View {
        FormScreen(
            title: "unbondRune".localized,
            validForm: $viewModel.validForm,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: "address".localized,
                isValid: viewModel.addressViewModel.field.valid,
                value: viewModel.addressViewModel.field.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .address
            ) {
                focusedFieldBinding = $0 ? .address : .amount
            } content: {
                FunctionAddressField(viewModel: viewModel.addressViewModel)
                    .focused($focusedField, equals: .address)
                FunctionAddressField(viewModel: viewModel.providerViewModel)
                    .focused($focusedField, equals: .address)
            }

            FormExpandableSection(
                title: viewModel.amountField.label ?? .empty,
                isValid: viewModel.amountField.valid,
                value: .empty,
                showValue: false,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) {
                focusedFieldBinding = $0 ? .amount : .address
            } content: {
                AmountTextField(
                    amount: $viewModel.amountField.value,
                    error: $viewModel.amountField.error,
                    ticker: viewModel.coin.chain.ticker,
                    type: .slider,
                    availableAmount: viewModel.bondNodeFormattedAmount,
                    decimals: 4,
                    percentage: $percentageSelected,
                ).focused($focusedField, equals: .amount)
            }
        }
        .onLoad {
            viewModel.onLoad()
            onAddressFill()
        }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .onChange(of: viewModel.addressViewModel.field.valid) { _, _ in
            onAddressFill()
        }
        .onChange(of: focusedFieldBinding) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
    }

    func onContinue() {
        switch focusedFieldBinding {
        case .address:
            focusedFieldBinding =  .amount
        case .amount, nil:
            if viewModel.amountField.valid, !viewModel.addressViewModel.field.valid {
                focusedField = .address
                return
            }

            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            onVerify(transactionBuilder)
        }
    }

    func onAddressFill() {
        focusedFieldBinding = viewModel.addressViewModel.field.valid ? .amount : .address
    }
}

#Preview {
    UnbondTransactionScreen(
        viewModel: UnbondTransactionViewModel(
            coin: .example,
            vault: .example,
            bondAddress: "thor1pe0pspu4ep85gxr5h9l6k49g024vemtr80hg4c"
        )
    ) { _ in }
}
