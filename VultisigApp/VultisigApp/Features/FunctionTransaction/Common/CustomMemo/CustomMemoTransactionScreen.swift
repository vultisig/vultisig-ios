//
//  CustomMemoTransactionScreen.swift
//  VultisigApp
//
//  Raw-memo `MsgDeposit` confirmation: the asset the deposit rides on, an
//  optional amount of it, and the memo itself.
//
//  The memo field is plain text with no formatter and no length cap, because
//  the whole point of this screen is that the app has no grammar for what the
//  user is writing. Continue is deliberately not gated on `validForm` (see
//  `FormScreen`) — the tap is what reveals the field errors, and the
//  view-model's `transactionBuilder` is the gate that actually closes.
//

import SwiftUI

struct CustomMemoTransactionScreen: View {
    enum FocusedField {
        case amount, memo
    }

    @StateObject var viewModel: CustomMemoTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State private var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?
    @State private var showAssetSelection: Bool = false

    var body: some View {
        FormScreen(
            title: "custom".localized,
            onContinue: onContinue
        ) {
            // The asset is staged through a sheet, so it is a picker row rather
            // than an expandable one — and it holds only the asset. Amount used
            // to live in here too, which meant collapsing a section labelled
            // "Asset" took the amount field with it, where nobody would think
            // to look for it.
            FormPickerSection(
                title: "asset".localized,
                isValid: viewModel.selectedAsset != nil,
                onTap: { showAssetSelection = true },
                valueView: { AssetSelectionFormCell(coin: viewModel.selectedAsset?.asset) }
            )

            FormExpandableSection(
                title: "amount".localized,
                isValid: viewModel.amountField.valid,
                value: viewModel.amountField.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) {
                focusedFieldBinding = $0 ? .amount : .memo
            } content: {
                AmountTextField(
                    amount: $viewModel.amountField.value,
                    error: $viewModel.amountField.error,
                    ticker: viewModel.selectedCoin?.ticker ?? .empty,
                    type: .button,
                    availableAmount: viewModel.selectedCoin?.balanceDecimal ?? .zero,
                    decimals: viewModel.selectedCoin?.decimals ?? 0,
                    percentage: $viewModel.percentageSelected
                )
                .focused($focusedField, equals: .amount)
            }

            FormExpandableSection(
                title: "customMemo".localized,
                isValid: viewModel.memoField.valid,
                value: viewModel.memoField.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .memo
            ) {
                focusedFieldBinding = $0 ? .memo : .amount
            } content: {
                CommonTextField(
                    text: $viewModel.memoField.value,
                    placeholder: viewModel.memoField.placeholder ?? .empty,
                    error: $viewModel.memoField.error,
                    isScrollable: true,
                    labelStyle: .secondary
                )
                .focused($focusedField, equals: .memo)
#if os(iOS)
                // THORChain and Maya memos are case-sensitive, and the software
                // keyboard capitalises the first character by default — it would
                // rewrite the user's string before the form ever sees it, which
                // is the one thing this screen must not do. `MemoTextField` on
                // the Send form disables it for the same reason.
                .textInputAutocapitalization(.never)
#endif
            }
        }
        .onLoad {
            viewModel.onLoad()
            // Opens on the memo: it is the only field this form always needs,
            // and the asset is already selected whenever the entry coin could
            // supply it.
            focusedFieldBinding = .memo
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
        .crossPlatformSheet(isPresented: $showAssetSelection) {
            AssetSelectionListScreen(
                isPresented: $showAssetSelection,
                selectedAsset: $viewModel.selectedAsset,
                dataSource: viewModel.assetsDataSource
            ) { showAssetSelection = false }
        }
    }

    func onContinue() {
        switch focusedFieldBinding {
        case .amount:
            focusedFieldBinding = .memo
        case .memo, nil:
            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            focusedFieldBinding = nil
            focusedField = nil
            onVerify(transactionBuilder)
        }
    }
}

#Preview {
    CustomMemoTransactionScreen(
        viewModel: CustomMemoTransactionViewModel(coin: .example, vault: .example)
    ) { _ in }
}
