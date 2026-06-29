//
//  SolanaWithdrawTransactionScreen.swift
//  VultisigApp
//
//  Withdraw confirmation for Solana native staking. The stake account and the
//  withdrawable amount are pre-resolved by the view-model; there's no amount
//  field (the whole withdrawable balance moves back to the wallet). The Continue
//  CTA is disabled until the account is fully inactive — while it cools down a
//  "available to withdraw in N epochs (~M days)" notice is shown.
//

import SwiftUI

struct SolanaWithdrawTransactionScreen: View {
    @StateObject private var viewModel: SolanaWithdrawTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: SolanaWithdrawTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    var body: some View {
        FormScreen(
            title: String(format: "solanaStakingWithdrawTitle".localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            isContinueDisabled: !viewModel.isWithdrawable || !viewModel.hasSufficientBalanceForFee,
            onContinue: onContinue
        ) {
            FormPickerSection(
                title: "solanaStakingStakeAccount".localized,
                isValid: true,
                onTap: {},
                valueView: { stakeAccountPreview }
            )
            .disabled(true)

            FormPickerSection(
                title: "solanaStakingWithdrawableAmount".localized,
                value: amountValue,
                isValid: true,
                onTap: {}
            )
            .disabled(true)

            if let cooldownMessage = viewModel.cooldownMessage {
                InfoBannerView(
                    description: cooldownMessage,
                    type: .info,
                    leadingIcon: "info"
                )
            }

            if !viewModel.hasSufficientBalanceForFee {
                InsufficientFeeNotice(ticker: viewModel.coin.ticker)
            }
        }
        .onLoad {
            viewModel.onLoad()
        }
    }

    private var amountValue: String {
        "\(viewModel.withdrawableAmount.formatToDecimal(digits: viewModel.coin.decimals)) \(viewModel.coin.ticker)"
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
