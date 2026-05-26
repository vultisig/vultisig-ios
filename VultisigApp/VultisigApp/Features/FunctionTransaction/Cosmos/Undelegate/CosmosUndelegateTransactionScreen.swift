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
            onContinue: onContinue
        ) {
            validatorSummary

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
                VStack(spacing: 12) {
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

                    unbondingLockNotice
                }
            }
        }
        .onLoad { viewModel.onLoad() }
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

    @ViewBuilder
    private var validatorSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("cosmosStakingValidatorPicker".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            HStack(spacing: 8) {
                Text(viewModel.validatorMoniker.isEmpty
                     ? truncated(viewModel.validatorAddress)
                     : viewModel.validatorMoniker)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var unbondingLockNotice: some View {
        if let message = viewModel.unbondingLockMessage {
            HStack(spacing: 8) {
                Icon(named: "info", color: Theme.colors.textTertiary, size: 14)
                Text(message)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
            }
            .padding(12)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(8)
        }
    }

    private func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }

    private func truncated(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return address.prefix(8) + "…" + address.suffix(4)
    }
}
