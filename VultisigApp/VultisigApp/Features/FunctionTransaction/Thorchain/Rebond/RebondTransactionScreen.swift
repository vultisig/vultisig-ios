//
//  RebondTransactionScreen.swift
//  VultisigApp
//
//  THORChain node REBOND confirmation: the node address and the address the
//  protocol rebonds to in one section, the optional partial amount in another.
//  Continue is deliberately not gated on `validForm` — see `FormScreen`;
//  `viewModel.transactionBuilder` returning nil is the enforcement, and the
//  tap is what reveals the field errors on a form the user has not touched.
//

import SwiftUI

struct RebondTransactionScreen: View {
    enum FocusedField {
        case node, newAddress, amount
    }

    @StateObject var viewModel: RebondTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        FormScreen(
            title: "Rebond".localized,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: "address".localized,
                isValid: viewModel.nodeViewModel.field.valid && viewModel.newAddressViewModel.field.valid,
                value: viewModel.nodeViewModel.field.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: [FocusedField.node, .newAddress]
            ) {
                focusedFieldBinding = $0 ? .node : nil
            } content: {
                VStack(spacing: 12) {
                    FunctionAddressField(viewModel: viewModel.nodeViewModel)
                        .focused($focusedField, equals: .node)
                    FunctionAddressField(viewModel: viewModel.newAddressViewModel)
                        .focused($focusedField, equals: .newAddress)
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
                focusedFieldBinding = $0 ? .amount : nil
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    CommonTextField(
                        text: $viewModel.amountField.value,
                        label: "rebondAmount".localized,
                        placeholder: viewModel.amountField.placeholder ?? .empty,
                        error: $viewModel.amountField.error,
                        labelStyle: .secondary
                    )
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .focused($focusedField, equals: .amount)

                    memoOnlyNote
                }
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .node
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
    }

    /// The amount is memo data, not a transfer: the builder attaches zero and
    /// the protocol reads the segment off the memo. Carried over verbatim from
    /// the legacy form, where it said the same thing in a hardcoded orange.
    var memoOnlyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(.circleInfo, color: Theme.colors.alertWarning, size: 14)
            Text("rebondNote".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.alertWarning)
            Spacer()
        }
    }

    func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}

#Preview {
    RebondTransactionScreen(
        viewModel: RebondTransactionViewModel(
            coin: .example,
            vault: .example,
            initialNodeAddress: nil
        )
    ) { _ in }
}
