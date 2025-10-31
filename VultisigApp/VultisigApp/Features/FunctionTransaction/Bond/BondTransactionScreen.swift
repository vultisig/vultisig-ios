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
    var onVerify: (SendTransaction) -> Void
    
    @State var focusedFieldBinding: FocusedField? = .none
    
    var body: some View {
        TransactionFormScreen(
            title: "bondRune".localized,
            validForm: $viewModel.validForm,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: "address".localized,
                isValid: viewModel.addressField.valid,
                value: viewModel.addressField.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .address
            ) {
                focusedFieldBinding = $0 ? .address : .amount
            } content: {
                AddressTextField(
                    address: $viewModel.addressField.value,
                    label: viewModel.addressField.label ?? .empty,
                    coin: viewModel.coin,
                    error: $viewModel.addressField.error
                ) {  viewModel.handle(addressResult: $0, isProvider: false) }
                
                AddressTextField(
                    address: $viewModel.providerField.value,
                    label: viewModel.providerField.label ?? .empty,
                    coin: viewModel.coin,
                    error: $viewModel.providerField.error
                ) {  viewModel.handle(addressResult: $0, isProvider: true) }
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
                    ticker: Chain.thorChain.ticker,
                    type: .button
                ) { viewModel.onPercentage($0) }
                
                CommonTextField(
                    text: $viewModel.operatorFee.value,
                    label: viewModel.operatorFee.label,
                    placeholder: viewModel.operatorFee.placeholder ?? .empty,
                    labelStyle: .secondary
                )
                .keyboardType(.decimalPad)
            }
        }
        .onLoad(perform: viewModel.onLoad)
    }
    
    func onContinue() {
        switch focusedFieldBinding {
        case .address:
            focusedFieldBinding =  .amount
        case .amount, nil:
            guard let tx = viewModel.buildTransaction() else { return }
            onVerify(tx)
        }
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
