//
//  IBCTransferTransactionScreen.swift
//  VultisigApp
//
//  IBC transfer: destination chain, address on it, amount, optional memo.
//
//  Continue is deliberately not gated on `validForm` (see `FormScreen`) — the
//  tap is what reveals the errors on a form the user has not touched, and
//  `viewModel.transactionBuilder` returning nil is the enforcement. It *is*
//  hard-disabled for a source asset with no IBC route at all, which is the
//  other case that doc describes: nothing the user can type would help.
//

import SwiftUI

struct IBCTransferTransactionScreen: View {
    enum FocusedField {
        case address, amount, memo
    }

    @StateObject var viewModel: IBCTransferTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State private var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?
    @State private var showDestinationSelection: Bool = false

    var body: some View {
        FormScreen(
            title: "ibcTransferTitle".localized,
            isContinueDisabled: viewModel.isContinueDisabled,
            onContinue: onContinue
        ) {
            if viewModel.hasNoDestinations {
                ErrorMessage(text: "ibcNoDestinationChains")
                    .padding(.top, 48)
            } else if !viewModel.hasSufficientBalanceForFee {
                // Without this the amount field would reject every number the
                // user types as "amount exceeded", because the spendable ceiling
                // has collapsed to zero.
                InsufficientFeeNotice(ticker: viewModel.coin.ticker)
            }

            FormPickerSection(
                title: "selectDestinationChain".localized,
                isValid: viewModel.selectedDestination != nil,
                onTap: { showDestinationSelection = true },
                valueView: { AssetSelectionFormCell(coin: viewModel.selectedDestination?.asset) }
            )
            .showIf(!viewModel.hasNoDestinations)

            FormExpandableSection(
                title: "destinationAddress".localized,
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
            }
            .showIf(!viewModel.hasNoDestinations)

            FormExpandableSection(
                title: "amount".localized,
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
                    ticker: viewModel.coin.ticker,
                    type: .button,
                    availableAmount: viewModel.spendableBalance,
                    decimals: viewModel.coin.decimals,
                    percentage: $viewModel.percentageSelected
                )
                .focused($focusedField, equals: .amount)
            }
            .showIf(!viewModel.hasNoDestinations)

            FormExpandableSection(
                title: "memoLabel".localized,
                isValid: true,
                value: viewModel.memoField.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .memo
            ) {
                focusedFieldBinding = $0 ? .memo : .amount
            } content: {
                CommonTextField(
                    text: $viewModel.memoField.value,
                    label: viewModel.memoField.label,
                    placeholder: viewModel.memoField.placeholder ?? .empty,
                    labelStyle: .secondary
                )
                .focused($focusedField, equals: .memo)
            }
            .showIf(!viewModel.hasNoDestinations)
        }
        .crossPlatformSheet(isPresented: $showDestinationSelection) {
            IBCDestinationSelectionScreen(
                isPresented: $showDestinationSelection,
                destinations: viewModel.destinations,
                selected: viewModel.selectedDestination
            ) { destination in
                viewModel.select(destination)
                showDestinationSelection = false
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
    IBCTransferTransactionScreen(
        viewModel: IBCTransferTransactionViewModel(
            coin: .example,
            vault: .example,
            destinationChain: nil
        )
    ) { _ in }
}
