//
//  TonLiquidStakeTransactionScreen.swift
//  VultisigApp
//
//  Tonstakers (TON liquid staking) deposit input. The pool is fixed
//  (Tonstakers), so unlike the nominator flow there is no pool picker — just
//  an amount field with the 1-TON minimum.
//

import SwiftUI

struct TonLiquidStakeTransactionScreen: View {
    enum FocusedField {
        case amount
    }

    @StateObject private var viewModel: TonLiquidStakeTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: TonLiquidStakeTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    @State private var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?
    @State private var percentageSelected: Double?

    var body: some View {
        FormScreen(
            title: "tonstakersStakeTitle".localized,
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

            VStack(alignment: .leading, spacing: 8) {
                infoRow(
                    "tonstakersDepositFee".localized,
                    "\(viewModel.depositFee.formatToDecimal(digits: 2)) \(viewModel.coin.chain.ticker)"
                )
                if let expected = viewModel.expectedTsTON(for: viewModel.amountField.value.toDecimal()) {
                    infoRow(
                        "tonstakersYouReceive".localized,
                        "≈ \(expected.formatToDecimal(digits: 4)) tsTON"
                    )
                }
            }

            Text(String(
                format: "tonstakersStakeNotice".localized,
                viewModel.depositFee.formatToDecimal(digits: 2),
                viewModel.coin.chain.ticker
            ))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)

            if !viewModel.hasSufficientBalanceForFee {
                InsufficientFeeNotice(ticker: viewModel.coin.chain.ticker)
            }
        }
        .onLoad {
            viewModel.onLoad()
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

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.colors.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .font(Theme.fonts.caption12)
    }

    private func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}
