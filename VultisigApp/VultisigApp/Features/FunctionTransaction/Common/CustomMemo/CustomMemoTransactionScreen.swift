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
            FormExpandableSection(
                title: "asset".localized,
                isValid: viewModel.amountField.valid,
                value: viewModel.selectedCoin?.ticker ?? .empty,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) {
                focusedFieldBinding = $0 ? .amount : .memo
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    assetSelector

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

    /// The picked asset, or an invitation to pick one. `AssetSelectionFormCell`
    /// renders nothing for a nil coin, and this form can legitimately open with
    /// nothing selected — a tappable placeholder is what keeps that state from
    /// looking like a broken screen.
    @ViewBuilder
    var assetSelector: some View {
        Button {
            showAssetSelection = true
        } label: {
            Group {
                if let asset = viewModel.selectedAsset?.asset {
                    AssetSelectionFormCell(coin: asset)
                } else {
                    assetPlaceholder
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var assetPlaceholder: some View {
        HStack(spacing: 4) {
            Text("selectToken".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            Icon(
                .chevronRight,
                color: Theme.colors.textPrimary,
                size: 20
            )
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .background(Theme.radius.pill.shape.fill(Theme.colors.bgSurface1))
    }

    func onContinue() {
        switch focusedFieldBinding {
        case .amount:
            focusedFieldBinding = .memo
        case .memo, nil:
            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            onVerify(transactionBuilder)
        }
    }
}

#Preview {
    CustomMemoTransactionScreen(
        viewModel: CustomMemoTransactionViewModel(coin: .example, vault: .example)
    ) { _ in }
}
