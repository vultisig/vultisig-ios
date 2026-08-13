//
//  SwitchTransactionScreen.swift
//  VultisigApp
//
//  Cosmos Hub → THORChain SWITCH confirmation: the THORChain address to credit,
//  the amount to move, and — when the route cannot carry a switch — a notice
//  saying so. The destination is not on this screen at all: it is THORChain's
//  inbound vault, resolved on the Continue tap.
//
//  Continue is deliberately not gated on `validForm` (see `FormScreen`), and
//  deliberately not hard-disabled on a halted route either: the halt is read
//  asynchronously and can lift while the form is open, so a button disabled on
//  a value fetched once would leave a user with a dead control after the chain
//  resumed. Every tap re-reads the route live — that read is both the retry and
//  the fund-safety gate — and refreshes the notice from the answer.
//

import SwiftUI

struct SwitchTransactionScreen: View {
    enum FocusedField {
        case address, amount
    }

    @StateObject var viewModel: SwitchTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State private var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        FormScreen(
            title: "Switch".localized,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: "thorchainAddress".localized,
                isValid: viewModel.thorAddressViewModel.field.valid,
                value: viewModel.thorAddressViewModel.field.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .address
            ) {
                focusedFieldBinding = $0 ? .address : .amount
            } content: {
                FunctionAddressField(viewModel: viewModel.thorAddressViewModel)
                    .focused($focusedField, equals: .address)
            }

            FormExpandableSection(
                title: viewModel.amountField.label ?? .empty,
                isValid: viewModel.amountField.valid,
                value: .empty,
                showValue: false,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) {
                focusedFieldBinding = $0 ? .amount : .address
            } content: {
                AmountTextField(
                    amount: $viewModel.amountField.value,
                    error: $viewModel.amountField.error,
                    ticker: viewModel.coin.ticker,
                    type: .button,
                    availableAmount: viewModel.coin.balanceDecimal,
                    decimals: viewModel.coin.decimals,
                    percentage: $viewModel.percentageSelected
                )
                .focused($focusedField, equals: .amount)
            }

            if let routeMessage = viewModel.routeMessage {
                routeNotice(message: routeMessage)
            }
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .amount
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
        .withLoading(isLoading: $viewModel.isLoading)
    }

    private func routeNotice(message: String) -> some View {
        HStack(spacing: 8) {
            Icon(.circleInfo, color: Theme.colors.alertWarning, size: 16)
            Text(message)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
        }
        .padding(14)
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.md.shape)
        .padding(.top, 8)
    }

    private func onContinue() {
        switch focusedFieldBinding {
        case .address:
            focusedFieldBinding = .amount
        case .amount, nil:
            Task { @MainActor in
                guard let transactionBuilder = await viewModel.prepareTransactionBuilder() else { return }
                onVerify(transactionBuilder)
            }
        }
    }
}

#Preview {
    SwitchTransactionScreen(
        viewModel: SwitchTransactionViewModel(coin: .example, vault: .example)
    ) { _ in }
}
