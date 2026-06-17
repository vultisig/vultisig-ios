//
//  YieldDepositScreen.swift
//  VultisigApp
//

import SwiftUI

/// Deposit form for a yield vault. Reuses the shared amount screen; on continue
/// it builds ONE prebuilt EVM payload that bundles the approve+deposit and routes
/// to the shared verify screen.
struct YieldDepositScreen: View {
    @StateObject private var viewModel: YieldDepositViewModel
    @Environment(\.router) private var router

    @State private var percentageSelected: Double?

    init(vault: Vault, providerID: DefiYieldProviderID) {
        _viewModel = StateObject(wrappedValue: YieldDepositViewModel(vault: vault, providerID: providerID))
    }

    var body: some View {
        ZStack {
            if let coinMeta = viewModel.coinMeta {
                AmountFunctionTransactionScreen(
                    title: viewModel.provider.presentation.depositTitleKey.localized,
                    coin: coinMeta,
                    availableAmount: viewModel.availableAmount,
                    percentageSelected: $percentageSelected,
                    percentageFieldType: .button,
                    amountField: viewModel.amountField,
                    validForm: $viewModel.validForm,
                    customViewPosition: .bottom
                ) {
                    Task { await handleVerify() }
                } customView: {
                    minimumDepositBanner
                }
            }
        }
        .withLoading(isLoading: $viewModel.isLoading)
        .task {
            await viewModel.onLoad()
        }
    }

    /// Non-closable info banner stating the product minimum (e.g. "Minimum deposit
    /// is 100 USDC."). Shown only for providers that declare a minimum.
    @ViewBuilder
    private var minimumDepositBanner: some View {
        if viewModel.hasMinimumDeposit {
            InfoBannerView(
                description: viewModel.minimumDepositText,
                type: .info,
                leadingIcon: "circle-info"
            )
        }
    }

    private func handleVerify() async {
        guard let payload = await viewModel.makeDepositPayload(),
              let displayTx = viewModel.displayTransaction() else { return }

        await MainActor.run {
            router.navigate(
                to: SendRoute.verify(
                    tx: displayTx,
                    retrySignal: SendRetrySignal(),
                    vault: viewModel.vault,
                    prebuiltKeysignPayload: payload
                )
            )
        }
    }
}
