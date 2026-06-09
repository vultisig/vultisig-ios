//
//  CosmosUndelegateTransactionScreen.swift
//  VultisigApp
//
//  Undelegate input form for LUNA / LUNC. Same shape as the delegate
//  screen minus the validator picker — the validator is pre-selected
//  by the caller (from the position card) and surfaced as read-only.
//  The 21-day unbonding-lock notice is inline so the user accepts the
//  lock before confirming.
//

import SwiftUI

struct CosmosUndelegateTransactionScreen: View {
    enum FocusedField {
        case amount
    }

    @StateObject private var viewModel: CosmosUndelegateTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: CosmosUndelegateTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    @State private var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    @State private var percentageSelected: Double?

    var body: some View {
        FormScreen(
            title: String(format: "cosmosStakingUndelegateTitle".localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            isContinueDisabled: !viewModel.hasSufficientBalanceForFee,
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
                    type: .slider,
                    availableAmount: viewModel.stakedBalance,
                    decimals: viewModel.coin.decimals,
                    percentage: $percentageSelected
                )
                .focused($focusedField, equals: .amount)
            }

            if !viewModel.hasSufficientBalanceForFee {
                InsufficientFeeNotice(ticker: viewModel.coin.ticker)
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .amount
            percentageSelected = 100
        }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .onChange(of: focusedFieldBinding) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
    }

    private func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}
