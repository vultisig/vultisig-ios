//
//  SolanaFinishMoveTransactionScreen.swift
//  VultisigApp
//
//  "Finish moving to B" confirmation — the resume step of a guided Solana
//  move-stake. The moved account has cooled down; the user confirms the
//  re-delegate to the destination validator. No amount field: the whole cooled
//  account moves to B.
//

import SwiftUI

struct SolanaFinishMoveTransactionScreen: View {
    @StateObject private var viewModel: SolanaFinishMoveTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: SolanaFinishMoveTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    var body: some View {
        FormScreen(
            title: String(format: "solanaFinishMoveTitle".localized, viewModel.destinationValidator.displayName),
            validForm: $viewModel.validForm,
            isContinueDisabled: !viewModel.hasSufficientBalanceForFee,
            onContinue: onContinue
        ) {
            FormPickerSection(
                title: "solanaMoveStakeSourceAccount".localized,
                isValid: true,
                onTap: {},
                valueView: { accountPreview }
            )
            .disabled(true)

            FormPickerSection(
                title: "solanaMoveStakeDestinationValidator".localized,
                isValid: true,
                onTap: {},
                valueView: { validatorPreview }
            )
            .disabled(true)

            InfoBannerView(
                description: "solanaFinishMoveNotice".localized,
                type: .info,
                leadingIcon: "info"
            )

            if !viewModel.hasSufficientBalanceForFee {
                InsufficientFeeNotice(ticker: viewModel.coin.ticker)
            }
        }
        .onLoad {
            viewModel.onLoad()
        }
    }

    private var accountPreview: some View {
        Text(viewModel.movedStakeAccount.pubkey)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var validatorPreview: some View {
        Text(viewModel.destinationValidator.displayName)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}
