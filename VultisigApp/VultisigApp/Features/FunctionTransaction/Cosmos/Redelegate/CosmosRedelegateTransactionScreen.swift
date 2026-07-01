//
//  CosmosRedelegateTransactionScreen.swift
//  VultisigApp
//
//  Redelegate input form for LUNA / LUNC. Amount first, then destination
//  picker via the shared `StakingValidatorPickerScreen` (source excluded).
//  If the source is under a 21-day redelegation cooldown, the cooldown
//  notice replaces the form and Continue is disabled.
//

import SwiftUI

struct CosmosRedelegateTransactionScreen: View {
    enum FocusedField {
        case amount
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

    @State private var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?
    @State private var percentageSelected: Double?
    @State private var showValidatorPicker: Bool = false

    var body: some View {
        FormScreen(
            title: String(format: "cosmosStakingRedelegateTitle".localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            isContinueDisabled: !viewModel.hasSufficientBalanceForFee,
            onContinue: onContinue
        ) {
            if let cooldownMessage = viewModel.cooldownBlockedMessage {
                cooldownNotice(message: cooldownMessage)
            } else {
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

                FormPickerSection(
                    title: "validator".localized,
                    isValid: viewModel.selectedDstValidator != nil,
                    onTap: { showValidatorPicker = true },
                    valueView: { selectedDestinationPreview }
                )

                if !viewModel.hasSufficientBalanceForFee {
                    InsufficientFeeNotice(ticker: viewModel.coin.ticker)
                }
            }
        }
        .crossPlatformSheet(isPresented: $showValidatorPicker) {
            StakingValidatorPickerScreen(
                isPresented: $showValidatorPicker,
                selectedValidator: $viewModel.selectedDstValidator,
                source: .cosmos(
                    chain: viewModel.coin.chain,
                    excludedValidators: viewModel.excludedDstValidators
                ),
                chainTicker: viewModel.coin.ticker,
                chainDecimals: viewModel.coin.decimals
            )
        }
        .onLoad {
            viewModel.onLoad()
            if viewModel.cooldownBlockedMessage == nil {
                focusedFieldBinding = .amount
                percentageSelected = 100
            }
        }
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
    private var selectedDestinationPreview: some View {
        if let validator = viewModel.selectedDstValidator {
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

    private func truncated(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return address.prefix(8) + "…" + address.suffix(4)
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
        guard viewModel.selectedDstValidator != nil else {
            showValidatorPicker = true
            return
        }
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}
