//
//  MergeTransactionScreen.swift
//  VultisigApp
//
//  Rujira MERGE confirmation: pick a mergeable token, enter an amount.
//  Continue is deliberately not gated on `validForm` — see the doc comment on
//  `FormScreen`; `viewModel.transactionBuilder` returning nil is the
//  enforcement, and the amount field carries the reason.
//

import SwiftUI

struct MergeTransactionScreen: View {
    enum FocusedField {
        case amount
    }

    @StateObject var viewModel: MergeTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?

    @State var showAssetSelection: Bool = false

    var body: some View {
        FormScreen(
            title: "Merge".localized,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: "asset".localized,
                isValid: viewModel.amountField.valid,
                value: viewModel.selectedAsset?.memoDenom ?? .empty,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) {
                focusedFieldBinding = $0 ? .amount : nil
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    assetSelector

                    CommonTextField(
                        text: $viewModel.amountField.value,
                        label: viewModel.amountLabel,
                        placeholder: viewModel.amountField.placeholder ?? .empty,
                        error: $viewModel.amountField.error,
                        labelStyle: .secondary
                    )
                    .focused($focusedField, equals: .amount)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                }
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .amount
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
        .crossPlatformSheet(isPresented: $showAssetSelection) {
            AssetSelectionListScreen(
                isPresented: $showAssetSelection,
                selectedAsset: Binding(
                    get: { viewModel.selectedAsset?.pickerAsset },
                    set: { viewModel.select(pickerAsset: $0) }
                ),
                dataSource: viewModel.assetsDataSource
            ) { showAssetSelection = false }
        }
    }

    var assetSelector: some View {
        Button {
            showAssetSelection = true
        } label: {
            if let selectedAsset = viewModel.selectedAsset {
                AssetSelectionFormCell(coin: selectedAsset.pickerAsset.asset)
                    .contentShape(Rectangle())
            } else {
                placeholder
            }
        }
        .buttonStyle(.plain)
    }

    var placeholder: some View {
        HStack(spacing: 4) {
            Text("selectTokenToMerge".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)

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
        .contentShape(Rectangle())
    }

    func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}

#Preview {
    MergeTransactionScreen(
        viewModel: MergeTransactionViewModel(
            coin: .example,
            vault: .example,
            initialDenom: nil
        )
    ) { _ in }
}
