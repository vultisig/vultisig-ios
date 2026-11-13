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

    private var balanceText: String {
        AmountFormatter.formatCryptoAmount(value: viewModel.tsTONBalanceDecimal, coin: TokensStore.tston)
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
                AmountTextField(
                    amount: $viewModel.amount,
                    error: $viewModel.amountError,
                    ticker: TokensStore.tston.ticker,
                    type: .button,
                    availableAmount: viewModel.tsTONBalanceDecimal,
                    decimals: Tonstakers.tsTONDecimals,
                    percentage: $viewModel.percentage
                )

                ContainerView {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(
                            title: "tonstakersPositionLabel".localized,
                            value: balanceText
                        )
                        if let expected = viewModel.expectedTON {
                            infoRow(
                                title: "tonstakersYouReceive".localized,
                                value: "≈ \(expected.formatToDecimal(digits: 4)) \(viewModel.coin.chain.ticker)"
                            )
                        }
                        infoRow(
                            title: "tonstakersAttachedValue".localized,
                            value: "\(viewModel.attachedValue.formatToDecimal(digits: 2)) \(viewModel.coin.chain.ticker)"
                        )
                    }
                }

                Text(String(
                    format: "tonstakersUnstakeNotice".localized,
                    viewModel.attachedValue.formatToDecimal(digits: 2),
                    viewModel.coin.chain.ticker
                ))
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
        .onChange(of: viewModel.amount) { _, _ in
            viewModel.validate()
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
