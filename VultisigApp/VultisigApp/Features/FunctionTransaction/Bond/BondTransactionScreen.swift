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
    @State var percentageSelected: Int?
    
    var body: some View {
        TransactionFormScreen(
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
                FunctionAddressField(viewModel: viewModel.addressViewModel)
                    .focused($focusedField, equals: .address)
                FunctionAddressField(viewModel: viewModel.providerViewModel)
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
                    ticker: Chain.thorChain.ticker,
                    type: .button,
                    availableAmount: viewModel.coin.balanceDecimal,
                    decimals: viewModel.coin.decimals,
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
        .onLoad {
            viewModel.onLoad()
            onAddressFill()
        }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .onChange(of: viewModel.addressViewModel.field.valid) { _, isValid in
            onAddressFill()
        }
        .onChange(of: viewModel.operatorFeeField.valid) { _, isValid in
            try? viewModel.operatorFeeField.validateErrors()
        }
        .onChange(of: focusedFieldBinding) { oldValue, newValue in
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
