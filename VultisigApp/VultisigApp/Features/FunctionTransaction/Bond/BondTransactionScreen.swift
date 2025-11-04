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
    @StateObject private var functionCallViewModel = FunctionCallViewModel()
    var onVerify: (SendTransaction) -> Void
    
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
                ) {
                    viewModel.handle(addressResult: $0, isProvider: false)
                }
                .focused($focusedField, equals: .address)
                
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
                .keyboardType(.decimalPad)
            }
        }
        .onLoad {
            Task {
                await loadGasInfo()
            }
            viewModel.onLoad()
            onAddressFill()
        }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .onChange(of: viewModel.addressField.valid) { _, isValid in
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
            if viewModel.amountField.valid, !viewModel.addressField.valid {
                focusedField = .address
                return
            }
            
            guard let tx = viewModel.buildTransaction() else { return }
            onVerify(tx)
        }
    }
    
    func onAddressFill() {
        focusedFieldBinding = viewModel.addressField.valid ? .amount : .address
    }
    
    func loadGasInfo() async {
        await functionCallViewModel.loadGasInfoForSending(tx: viewModel.sendTx)
        await functionCallViewModel.loadFastVault(tx: viewModel.sendTx, vault: viewModel.vault)
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
