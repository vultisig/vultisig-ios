//
//  CosmosDelegateTransactionScreen.swift
//  VultisigApp
//
//  Delegate input form for LUNA / LUNC. Two sections — validator picker
//  (opens the `ValidatorSelectionScreen` sheet) and amount (uses the
//  existing `AmountTextField`). Mirrors `BondTransactionScreen` shape.
//

import SwiftUI

struct CosmosDelegateTransactionScreen: View {
    enum FocusedField {
        case amount
    }

    @StateObject private var viewModel: CosmosDelegateTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: CosmosDelegateTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    @State private var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?
    @State private var percentageSelected: Double?
    @State private var showValidatorPicker: Bool = false

    var body: some View {
        FormScreen(
            title: String(format: "cosmosStakingDelegateTitle".localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            onContinue: onContinue
        ) {
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
                AmountTextField(
                    amount: $viewModel.amountField.value,
                    error: $viewModel.amountField.error,
                    ticker: viewModel.coin.ticker,
                    type: .button,
                    availableAmount: viewModel.stakeableBalance,
                    decimals: viewModel.coin.decimals,
                    percentage: $percentageSelected
                )
                .focused($focusedField, equals: .amount)
            }

            FormPickerSection(
                title: "cosmosStakingValidatorPicker".localized,
                showValue: viewModel.selectedValidator != nil,
                onTap: { showValidatorPicker = true },
                valueView: { selectedValidatorPreview }
            )
        }
        .crossPlatformSheet(isPresented: $showValidatorPicker) {
            ValidatorSelectionScreen(
                isPresented: $showValidatorPicker,
                selectedValidator: $viewModel.selectedValidator,
                chain: viewModel.coin.chain,
                chainTicker: viewModel.coin.ticker
            )
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .amount
        }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .onChange(of: viewModel.selectedValidator) { _, _ in
            focusedFieldBinding = .amount
        }
        .onChange(of: focusedFieldBinding) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
    }

    @ViewBuilder
    private var selectedValidatorPreview: some View {
        if let validator = viewModel.selectedValidator {
            let display = validator.moniker.isEmpty
                ? truncated(validator.operatorAddress)
                : validator.moniker
            HStack(spacing: 8) {
                KeybaseAvatarView(
                    identity: validator.identity,
                    monogram: String(display.prefix(1)).uppercased(),
                    size: 20
                )
                Text(display)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            EmptyView()
        }
    }

    private func onContinue() {
        guard viewModel.selectedValidator != nil else {
            showValidatorPicker = true
            return
        }
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }

    private func truncated(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return address.prefix(8) + "…" + address.suffix(4)
    }
}
