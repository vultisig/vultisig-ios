//
//  CosmosRedelegateTransactionScreen.swift
//  VultisigApp
//
//  Redelegate input form for LUNA / LUNC. Source validator read-only,
//  destination via the shared `ValidatorSelectionScreen` (source
//  excluded). If the source is under a 21-day redelegation cooldown,
//  the cooldown notice replaces the amount section and Continue is
//  disabled.
//

import SwiftUI

struct CosmosRedelegateTransactionScreen: View {
    enum FocusedField {
        case destination, amount
    }

    @StateObject private var viewModel: CosmosRedelegateTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: CosmosRedelegateTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    @State private var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    @State private var percentageSelected: Double?
    @State private var showValidatorPicker: Bool = false

    var body: some View {
        FormScreen(
            title: String(format: "cosmosStakingRedelegateTitle".localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            onContinue: onContinue
        ) {
            sourceSummary

            if let cooldownMessage = viewModel.cooldownBlockedMessage {
                cooldownNotice(message: cooldownMessage)
            } else {
                FormExpandableSection(
                    title: "cosmosStakingRedelegateDestination".localized,
                    isValid: viewModel.selectedDstValidator != nil,
                    value: viewModel.selectedDstValidator?.moniker ?? "",
                    showValue: viewModel.selectedDstValidator != nil,
                    focusedField: $focusedFieldBinding,
                    focusedFieldEquals: .destination
                ) {
                    focusedFieldBinding = $0 ? .destination : .amount
                    if $0 {
                        showValidatorPicker = true
                    }
                } content: {
                    destinationButton
                }

                FormExpandableSection(
                    title: viewModel.amountField.label ?? .empty,
                    isValid: viewModel.amountField.valid,
                    value: .empty,
                    showValue: false,
                    focusedField: $focusedFieldBinding,
                    focusedFieldEquals: .amount
                ) {
                    focusedFieldBinding = $0 ? .amount : .destination
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
            }
        }
        .crossPlatformSheet(isPresented: $showValidatorPicker) {
            ValidatorSelectionScreen(
                isPresented: $showValidatorPicker,
                selectedValidator: $viewModel.selectedDstValidator,
                chain: viewModel.coin.chain,
                chainTicker: viewModel.coin.ticker,
                excludedValidators: viewModel.excludedDstValidators
            )
        }
        .onLoad { viewModel.onLoad() }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .onChange(of: viewModel.selectedDstValidator) { _, _ in
            focusedFieldBinding = .amount
        }
        .onChange(of: focusedFieldBinding) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
    }

    @ViewBuilder
    private var sourceSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("cosmosStakingRedelegateSource".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            HStack(spacing: 8) {
                Text(viewModel.validatorSrcMoniker.isEmpty
                     ? truncated(viewModel.validatorSrcAddress)
                     : viewModel.validatorSrcMoniker)
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
    private var destinationButton: some View {
        Button {
            showValidatorPicker = true
        } label: {
            HStack(spacing: 8) {
                if let validator = viewModel.selectedDstValidator {
                    Text(validator.moniker.isEmpty
                         ? truncated(validator.operatorAddress)
                         : validator.moniker)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                } else {
                    Text("cosmosStakingSelectValidator".localized)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer()
                Icon(named: "chevron-right", color: Theme.colors.textTertiary, size: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func cooldownNotice(message: String) -> some View {
        HStack(spacing: 8) {
            Icon(named: "info", color: Theme.colors.alertWarning, size: 16)
            Text(message)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
        }
        .padding(14)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 8)
    }

    private func onContinue() {
        switch focusedFieldBinding {
        case .destination:
            showValidatorPicker = true
        case .amount, .none:
            guard viewModel.selectedDstValidator != nil else {
                focusedFieldBinding = .destination
                showValidatorPicker = true
                return
            }
            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            onVerify(transactionBuilder)
        }
    }

    private func truncated(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return address.prefix(8) + "…" + address.suffix(4)
    }
}
