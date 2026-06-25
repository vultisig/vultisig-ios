//
//  TonStakeTransactionScreen.swift
//  VultisigApp
//
//  TON nominator-pool stake input. Add-more reuses the existing pool address
//  (amount-only); a first-time stake also exposes a validated pool-address
//  field. Mirrors `CosmosDelegateTransactionScreen` shape.
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

    var body: some View {
        FormScreen(
            title: String(format: "stakeCoin".localized, viewModel.coin.chain.ticker),
            validForm: $viewModel.validForm,
            isContinueDisabled: !viewModel.hasSufficientBalanceForFee,
            onContinue: onContinue
        ) {
            if viewModel.isFirstTimeStake {
                AddressTextField(
                    address: $viewModel.poolAddress,
                    label: "tonStakingPoolAddress".localized,
                    coin: viewModel.coin,
                    error: $viewModel.poolAddressError
                ) { result in
                    if let result {
                        viewModel.poolAddress = result.address
                    }
                    viewModel.validatePoolAddress()
                }
            }

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

            if !viewModel.hasSufficientBalanceForFee {
                InsufficientFeeNotice(ticker: viewModel.coin.chain.ticker)
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = viewModel.isFirstTimeStake ? nil : .amount
        }
        .onChange(of: viewModel.poolAddress) { _, _ in
            viewModel.validatePoolAddress()
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
        if viewModel.isFirstTimeStake, !viewModel.isPoolAddressValid {
            viewModel.validatePoolAddress()
            return
        }
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}
