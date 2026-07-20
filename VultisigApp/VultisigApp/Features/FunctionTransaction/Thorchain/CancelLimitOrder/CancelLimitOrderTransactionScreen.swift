//
//  CancelLimitOrderTransactionScreen.swift
//  VultisigApp
//
//  Confirmation for cancelling a resting THORChain limit order. There is no
//  input — the order is fully identified by the time we get here — so the screen
//  exists to state what cancelling actually does before the user signs.
//

import SwiftUI

struct CancelLimitOrderTransactionScreen: View {
    @StateObject private var viewModel: CancelLimitOrderTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    @State private var validForm: Bool = true

    init(
        viewModel: CancelLimitOrderTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    var body: some View {
        FormScreen(
            title: "limitSwap.cancel.title".localized,
            fixedHeight: false,
            validForm: $validForm,
            isContinueDisabled: viewModel.transactionBuilder == nil,
            onContinue: onContinue
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ContainerView {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(
                            title: "limitSwap.cancel.orderLabel".localized,
                            value: "\(viewModel.request.sourceAsset) → \(viewModel.request.targetAsset)"
                        )
                        Separator(color: Theme.colors.border, opacity: 1)
                        infoRow(
                            title: "limitSwap.detail.copyTxHash".localized,
                            value: viewModel.request.inboundTxHash,
                            truncate: true
                        )
                    }
                }

                // What actually happens on-chain: the order closes, anything
                // already filled stays paid out, and the unfilled remainder is
                // refunded. Said plainly because a user cancelling a partially
                // filled order otherwise has no way to know the filled part is
                // not coming back.
                Text("limitSwap.cancel.explanation".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)

                // ⚠️ Stated with the exact amount, before signing. An L1 cancel
                // must attach a coin for Bifrost to observe it at all, and
                // THORNode donates whatever arrives to the pool with no refund
                // path. On DOGE that is two whole coins — a generic "network
                // fees apply" would be actively misleading.
                if let donated = viewModel.donatedAmountDisplay {
                    WarningView(text: String(format: "limitSwap.cancel.donatedDust".localized, donated))
                }

                if let resolutionError = viewModel.resolutionError {
                    WarningView(text: resolutionError)
                }

                if let balanceError = viewModel.balanceErrorMessage {
                    WarningView(text: balanceError)
                }

                if viewModel.hasDuplicateWarning {
                    // THORChain addresses orders by (assets, ratio) + sender and
                    // cancels the FIRST match — never by tx hash. With more than
                    // one identical resting order we genuinely cannot promise
                    // which closes, so we say so rather than implying certainty.
                    WarningView(text: "limitSwap.cancel.duplicateWarning".localized)
                }

                if !viewModel.hasSufficientBalance {
                    InsufficientFeeNotice(ticker: viewModel.coin.chain.ticker)
                }

                Spacer()
            }
        }
        .task { await viewModel.onLoad() }
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
