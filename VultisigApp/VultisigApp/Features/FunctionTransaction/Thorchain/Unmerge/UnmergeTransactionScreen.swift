//
//  UnmergeTransactionScreen.swift
//  VultisigApp
//
//  THORChain RUJI UNMERGE confirmation: the merged token in a picker row, the
//  share count beneath it. The amount is typed in *shares*, not in the token —
//  a share is worth more than one token and the two drift apart as the pool
//  earns — so the field's unit reads "Shares", as the legacy form's label did.
//
//  Continue is deliberately not gated on `validForm` (see `FormScreen`);
//  `viewModel.transactionBuilder` returning nil is the enforcement, and the tap
//  is what reveals the error on a form the user has not touched.
//

import SwiftUI

struct UnmergeTransactionScreen: View {
    enum FocusedField {
        case amount
    }

    @StateObject var viewModel: UnmergeTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State private var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?
    @State private var showTokenSelection: Bool = false

    var body: some View {
        FormScreen(
            title: "Withdraw RUJI".localized,
            onContinue: onContinue
        ) {
            FormPickerSection(
                title: "selectAsset".localized,
                isValid: viewModel.selectedToken != nil,
                onTap: { showTokenSelection = true },
                valueView: { AssetSelectionFormCell(coin: viewModel.selectedToken?.asset) }
            )

            FormExpandableSection(
                title: viewModel.sharesLabel,
                isValid: viewModel.amountField.valid,
                value: .empty,
                showValue: false,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) {
                focusedFieldBinding = $0 ? .amount : nil
            } content: {
                AmountTextField(
                    amount: $viewModel.amountField.value,
                    error: $viewModel.amountField.error,
                    ticker: "sharesLabel".localized,
                    type: .button,
                    availableAmount: viewModel.availableAmount,
                    decimals: UnmergeShares.decimals,
                    percentage: $viewModel.percentageSelected
                )
                .focused($focusedField, equals: .amount)
            }
        }
        .crossPlatformSheet(isPresented: $showTokenSelection) {
            AssetSelectionListScreen(
                isPresented: $showTokenSelection,
                selectedAsset: Binding(
                    get: { viewModel.selectedToken },
                    set: { asset in
                        guard let asset else { return }
                        viewModel.select(asset)
                    }
                ),
                dataSource: viewModel.assetsDataSource
            ) {
                showTokenSelection = false
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .amount
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
    }

    func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}

#Preview {
    UnmergeTransactionScreen(
        viewModel: UnmergeTransactionViewModel(
            coin: .example,
            vault: .example,
            initialDenom: nil
        )
    ) { _ in }
}
