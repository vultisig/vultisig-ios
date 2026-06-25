//
//  TonStakeTransactionScreen.swift
//  VultisigApp
//
//  TON nominator-pool stake input. Add-more reuses the existing pool address
//  (amount-only); a first-time stake exposes a pool picker (mirroring the
//  Cosmos validator picker). Mirrors `CosmosDelegateTransactionScreen` shape.
//

import SwiftUI

struct TonStakeTransactionScreen: View {
    enum FocusedField {
        case amount
    }

    @StateObject private var viewModel: TonStakeTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: TonStakeTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    @State private var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?
    @State private var percentageSelected: Double?
    @State private var showPoolPicker: Bool = false

    var body: some View {
        FormScreen(
            title: String(format: "stakeCoin".localized, viewModel.coin.chain.ticker),
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
                    ticker: viewModel.coin.chain.ticker,
                    type: .button,
                    availableAmount: viewModel.maxStakeableAmount,
                    decimals: viewModel.coin.decimals,
                    percentage: $percentageSelected
                )
                .focused($focusedField, equals: .amount)
            }

            if viewModel.isFirstTimeStake {
                FormPickerSection(
                    title: "tonStakingPoolPicker".localized,
                    isValid: viewModel.selectedPool != nil,
                    onTap: { showPoolPicker = true },
                    valueView: { selectedPoolPreview }
                )
            }

            if !viewModel.hasSufficientBalanceForFee {
                InsufficientFeeNotice(ticker: viewModel.coin.chain.ticker)
            }
        }
        .crossPlatformSheet(isPresented: $showPoolPicker) {
            TonPoolSelectionScreen(
                isPresented: $showPoolPicker,
                selectedPool: $viewModel.selectedPool,
                ticker: viewModel.coin.chain.ticker,
                decimals: viewModel.coin.decimals
            )
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .amount
        }
        .onChange(of: viewModel.selectedPool) { _, _ in
            // Re-run validation so the min-stake check picks up the new pool.
            viewModel.validateErrors()
            focusedFieldBinding = .amount
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

    @ViewBuilder
    private var selectedPoolPreview: some View {
        if let pool = viewModel.selectedPool {
            HStack(spacing: 8) {
                KeybaseAvatarView(
                    identity: nil,
                    monogram: String((pool.name.isEmpty ? pool.address : pool.name).prefix(1)).uppercased(),
                    size: 20
                )
                Text(pool.name.isEmpty ? pool.address : pool.name)
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
        if viewModel.isFirstTimeStake, viewModel.selectedPool == nil {
            showPoolPicker = true
            return
        }
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}
