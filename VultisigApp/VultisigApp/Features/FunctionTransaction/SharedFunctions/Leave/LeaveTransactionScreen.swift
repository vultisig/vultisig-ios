//
//  LeaveTransactionScreen.swift
//  VultisigApp
//
//  Node LEAVE confirmation. One section, one field: the node address the
//  memo names. Continue is deliberately not gated on `validForm` — see the
//  doc comment on `FormScreen`; `viewModel.transactionBuilder` returning nil
//  is the enforcement.
//

import SwiftUI

struct LeaveTransactionScreen: View {
    enum FocusedField {
        case address
    }

    @StateObject var viewModel: LeaveTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        FormScreen(
            title: "Leave".localized,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: "nodeAddress".localized,
                isValid: viewModel.addressViewModel.field.valid,
                value: viewModel.addressViewModel.field.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .address
            ) {
                focusedFieldBinding = $0 ? .address : nil
            } content: {
                FunctionAddressField(viewModel: viewModel.addressViewModel)
                    .focused($focusedField, equals: .address)
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .address
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
    }

    func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}

#Preview {
    LeaveTransactionScreen(
        viewModel: LeaveTransactionViewModel(
            coin: .example,
            vault: .example,
            initialNodeAddress: nil
        )
    ) { _ in }
}
