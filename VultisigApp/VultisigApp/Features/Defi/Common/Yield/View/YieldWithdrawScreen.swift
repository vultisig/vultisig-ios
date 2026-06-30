//
//  YieldWithdrawScreen.swift
//  VultisigApp
//

import SwiftUI

/// Generic withdraw form for a yield vault, built on the shared
/// `AmountFunctionTransactionScreen` (slider amount entry, defaulting to 100%).
/// Builds the withdraw/requestRedeem payload (chosen by liquidity) and routes to
/// the shared verify screen with a display-only USDC transaction.
struct YieldWithdrawScreen: View {
    @StateObject private var viewModel: YieldWithdrawViewModel
    @Environment(\.router) private var router

    init(vault: Vault, providerID: DefiYieldProviderID, model: YieldViewModel) {
        _viewModel = StateObject(
            wrappedValue: YieldWithdrawViewModel(
                vault: vault,
                providerID: providerID,
                availableBalance: model.depositedBalance
            )
        )
    }

    private var presentation: YieldPresentation { viewModel.provider.presentation }

    var body: some View {
        ZStack {
            if let coinMeta = viewModel.coinMeta {
                AmountFunctionTransactionScreen(
                    title: presentation.withdrawTitleKey.localized,
                    coin: coinMeta,
                    availableAmount: viewModel.availableBalance,
                    percentageSelected: $viewModel.percentageSelected,
                    percentageFieldType: .slider,
                    amountField: viewModel.amountField,
                    validForm: $viewModel.validForm,
                    customViewPosition: .bottom
                ) {
                    Task { await handleWithdraw() }
                } customView: {
                    customView
                }
            }
        }
        .withLoading(isLoading: $viewModel.isLoading)
        .onLoad { viewModel.onLoad() }
    }

    @ViewBuilder
    private var customView: some View {
        VStack(spacing: 12) {
            if let error = viewModel.error {
                InfoBannerView(description: error.localizedDescription, type: .error, leadingIcon: "triangle-alert")
            }
            if viewModel.provider.hasWindowedRedemption {
                InfoBannerView(
                    description: "yieldRedemptionWindowNote".localized,
                    type: .info,
                    leadingIcon: "circle-info"
                )
            }
            if viewModel.nativeGasBalance <= 0 {
                InfoBannerView(
                    description: presentation.ethRequiredKey.localized,
                    type: .warning,
                    leadingIcon: "triangle-alert"
                )
            }
        }
    }

    private func handleWithdraw() async {
        guard let result = await viewModel.buildPayload(),
              let displayTx = viewModel.displayTransaction(recipient: result.recipient) else { return }

        await MainActor.run {
            router.navigate(
                to: SendRoute.verify(
                    tx: displayTx,
                    retrySignal: SendRetrySignal(),
                    vault: viewModel.vault,
                    prebuiltKeysignPayload: result.payload
                )
            )
        }
    }
}
