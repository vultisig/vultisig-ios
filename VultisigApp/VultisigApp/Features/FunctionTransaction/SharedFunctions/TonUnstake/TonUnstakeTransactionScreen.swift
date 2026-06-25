//
//  TonUnstakeTransactionScreen.swift
//  VultisigApp
//
//  TON nominator-pool unstake confirmation. Standard nominator pools support
//  full withdrawal only, so there is no amount input — the screen confirms the
//  full-withdrawal "w" message to the existing pool.
//

import SwiftUI

struct TonUnstakeTransactionScreen: View {
    @StateObject private var viewModel: TonUnstakeTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    @State private var validForm: Bool = true

    init(
        viewModel: TonUnstakeTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    private var stakedAmountText: String {
        AmountFormatter.formatCryptoAmount(value: viewModel.stakedAmount, coin: viewModel.coin.toCoinMeta())
    }

    var body: some View {
        FormScreen(
            title: String(format: "unstakeCoin".localized, viewModel.coin.chain.ticker),
            fixedHeight: false,
            validForm: $validForm,
            isContinueDisabled: !viewModel.hasSufficientBalance,
            onContinue: onContinue
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ContainerView {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(
                            title: String(format: "stakedCoin".localized, viewModel.coin.chain.ticker),
                            value: stakedAmountText
                        )
                        Separator(color: Theme.colors.border, opacity: 1)
                        infoRow(
                            title: "tonStakingPoolAddress".localized,
                            value: viewModel.poolAddress,
                            truncate: true
                        )
                    }
                }

                Text("tonUnstakeFullWithdrawalNotice".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)

                if !viewModel.hasSufficientBalance {
                    InsufficientFeeNotice(ticker: viewModel.coin.chain.ticker)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func infoRow(title: String, value: String, truncate: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(truncate ? .middle : .tail)
                .multilineTextAlignment(.trailing)
        }
    }

    private func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}
