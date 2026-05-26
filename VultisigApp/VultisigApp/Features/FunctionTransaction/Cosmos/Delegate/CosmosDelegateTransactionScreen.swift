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
        case validator, amount
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

    @State private var focusedFieldBinding: FocusedField? = .amount
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
                focusedFieldBinding = $0 ? .amount : .validator
            } content: {
                VStack(spacing: 12) {
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

                    gasReservationInfo
                }
            }

            FormExpandableSection(
                title: "cosmosStakingValidatorPicker".localized,
                isValid: viewModel.selectedValidator != nil,
                value: viewModel.selectedValidator?.moniker ?? "",
                showValue: viewModel.selectedValidator != nil,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .validator
            ) {
                focusedFieldBinding = $0 ? .validator : .amount
                if $0 {
                    showValidatorPicker = true
                }
            } content: {
                validatorButton
            }
        }
        .crossPlatformSheet(isPresented: $showValidatorPicker) {
            ValidatorSelectionScreen(
                isPresented: $showValidatorPicker,
                selectedValidator: $viewModel.selectedValidator,
                chain: viewModel.coin.chain,
                chainTicker: viewModel.coin.ticker
            )
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
    private var validatorButton: some View {
        Button {
            showValidatorPicker = true
        } label: {
            HStack(spacing: 8) {
                if let validator = viewModel.selectedValidator {
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

    @ViewBuilder
    private var gasReservationInfo: some View {
        if let message = viewModel.gasReservationMessage {
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
        switch focusedFieldBinding {
        case .validator:
            showValidatorPicker = true
        case .amount, .none:
            guard viewModel.selectedValidator != nil else {
                focusedFieldBinding = .validator
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
