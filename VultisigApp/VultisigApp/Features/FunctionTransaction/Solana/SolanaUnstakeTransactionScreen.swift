//
//  SolanaUnstakeTransactionScreen.swift
//  VultisigApp
//
//  Deactivate (unstake) confirmation for Solana native staking. The stake
//  account is pre-selected by the caller, so there's no amount field — the
//  screen surfaces the account and the ~1-epoch cooldown notice, then the user
//  confirms. Mirrors `CosmosUndelegateTransactionScreen` minus the amount.
//

import SwiftUI

struct SolanaUnstakeTransactionScreen: View {
    @StateObject private var viewModel: SolanaUnstakeTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: SolanaUnstakeTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    var body: some View {
        FormScreen(
            title: String(format: "solanaStakingUnstakeTitle".localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            isContinueDisabled: !viewModel.hasSufficientBalanceForFee,
            onContinue: onContinue
        ) {
            FormPickerSection(
                title: "solanaStakingStakeAccount".localized,
                isValid: true,
                onTap: {},
                valueView: { stakeAccountPreview }
            )
            .disabled(true)

            InfoBannerView(
                description: viewModel.cooldownMessage,
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

    private var stakeAccountPreview: some View {
        Text(viewModel.stakeAccount.pubkey)
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
