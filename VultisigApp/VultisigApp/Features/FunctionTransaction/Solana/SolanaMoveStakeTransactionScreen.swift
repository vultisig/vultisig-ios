//
//  SolanaMoveStakeTransactionScreen.swift
//  VultisigApp
//
//  Move-stake (redelegate A → B) input form for Solana native staking. The
//  source account is pre-selected by the caller; the user picks a destination
//  validator (reusing `SolanaValidatorSelectionScreen`). The screen explains
//  that a move is multi-step and spans epochs — it deactivates the account now,
//  then the user returns to finish moving to B once it has cooled down.
//

import SwiftUI

struct SolanaMoveStakeTransactionScreen: View {
    @StateObject private var viewModel: SolanaMoveStakeTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: SolanaMoveStakeTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    @State private var showValidatorPicker: Bool = false

    var body: some View {
        FormScreen(
            title: String(format: "solanaMoveStakeTitle".localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            isContinueDisabled: !viewModel.hasSufficientBalanceForFee,
            onContinue: onContinue
        ) {
            FormPickerSection(
                title: "solanaMoveStakeSourceAccount".localized,
                isValid: true,
                onTap: {},
                valueView: { sourceAccountPreview }
            )
            .disabled(true)

            FormPickerSection(
                title: "solanaMoveStakeDestinationValidator".localized,
                isValid: viewModel.selectedValidator != nil,
                onTap: { showValidatorPicker = true },
                valueView: { selectedValidatorPreview }
            )

            InfoBannerView(
                description: viewModel.multiStepMessage,
                type: .info,
                leadingIcon: "info"
            )

            if !viewModel.hasSufficientBalanceForFee {
                InsufficientFeeNotice(ticker: viewModel.coin.ticker)
            }
        }
        .crossPlatformSheet(isPresented: $showValidatorPicker) {
            SolanaValidatorSelectionScreen(
                isPresented: $showValidatorPicker,
                selectedValidator: $viewModel.selectedValidator,
                chainTicker: viewModel.coin.ticker,
                chainDecimals: viewModel.coin.decimals
            )
        }
        .onLoad {
            viewModel.onLoad()
        }
        .onChange(of: viewModel.selectedValidator) { _, newValue in
            viewModel.validForm = newValue != nil
        }
    }

    private var sourceAccountPreview: some View {
        Text(viewModel.sourceStakeAccount.pubkey)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private var selectedValidatorPreview: some View {
        if let validator = viewModel.selectedValidator {
            Text(validator.displayName)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
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
}
