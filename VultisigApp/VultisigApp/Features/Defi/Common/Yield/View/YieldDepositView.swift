//
//  YieldDepositView.swift
//  VultisigApp
//

import SwiftUI

/// Deposit form for a yield vault. Reuses the shared amount screen; on continue
/// it builds a prebuilt EVM payload (approve-then-deposit) and routes to the
/// shared verify screen.
struct YieldDepositView: View {
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
                    validForm: $viewModel.validForm
                ) {
                    Task { await handleVerify() }
                } customView: {
                    EmptyView()
                }
            }
        }
        .withLoading(isLoading: $viewModel.isLoading)
        .task {
            await viewModel.onLoad()
        }
    }

    private func handleVerify() async {
        guard let result = await viewModel.makeNextPayload(),
              let displayTx = viewModel.displayTransaction() else { return }

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
