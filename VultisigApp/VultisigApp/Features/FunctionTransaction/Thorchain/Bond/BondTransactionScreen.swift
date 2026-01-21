//
//  BondTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct BondTransactionScreen: View {
    enum FocusedField {
        case address, amount
    }

    @StateObject var viewModel: BondTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    @State var percentageSelected: Double?

    var body: some View {
        FormScreen(
            title: "bondRune".localized,
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
                VStack(spacing: 12) {
                    FunctionAddressField(viewModel: viewModel.addressViewModel)
                        .focused($focusedField, equals: .address)
                    FunctionAddressField(viewModel: viewModel.providerViewModel)
                }
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
                VStack(spacing: 12) {
                    AmountTextField(
                        amount: $viewModel.amountField.value,
                        error: $viewModel.amountField.error,
                        ticker: Chain.thorChain.ticker,
                        type: .button,
                        availableAmount: viewModel.coin.balanceDecimal,
                        decimals: 4, // keep 4 decimals
                        percentage: $percentageSelected,
                    ).focused($focusedField, equals: .amount)

                    CommonTextField(
                        text: $viewModel.operatorFeeField.value,
                        label: viewModel.operatorFeeField.label,
                        placeholder: viewModel.operatorFeeField.placeholder ?? .empty,
                        error: $viewModel.operatorFeeField.error,
                        labelStyle: .secondary
                    )
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                }
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
        .onChange(of: viewModel.operatorFeeField.valid) { _, _ in
            try? viewModel.operatorFeeField.validateErrors()
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
    BondTransactionScreen(
        viewModel: BondTransactionViewModel(
            coin: .example,
            vault: .example,
            initialBondAddress: nil
        )
    ) { _ in }
}
