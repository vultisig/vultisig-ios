//
//  TonLiquidUnstakeTransactionScreen.swift
//  VultisigApp
//
//  Tonstakers (TON liquid staking) unstake confirmation. Burns the user's full
//  tsTON balance via a jetton burn to their tsTON jetton wallet; the pool
//  returns TON instantly when liquid, otherwise via a ~18h withdrawal NFT.
//

import SwiftUI

struct TonLiquidUnstakeTransactionScreen: View {
    @StateObject private var viewModel: TonLiquidUnstakeTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    @State private var validForm: Bool = true

    init(
        viewModel: TonLiquidUnstakeTransactionViewModel,
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
            title: "tonstakersUnstakeTitle".localized,
            fixedHeight: false,
            validForm: $validForm,
            isContinueDisabled: !viewModel.canContinue,
            onContinue: onContinue
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ContainerView {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(
                            title: "tonstakersPositionLabel".localized,
                            value: stakedAmountText
                        )
                    }
                }

                Text("tonstakersUnstakeNotice".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)

                if !viewModel.isLoading, !viewModel.hasSufficientBalance {
                    InsufficientFeeNotice(ticker: viewModel.coin.chain.ticker)
                }

                Spacer()
            }
        }
        .onLoad {
            Task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
    }

    private func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}
