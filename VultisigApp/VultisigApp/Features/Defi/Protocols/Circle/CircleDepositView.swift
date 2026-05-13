//
//  CircleDepositView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI

struct CircleDepositView: View {
    @StateObject private var viewModel: CircleDepositViewModel
    @Environment(\.router) var router

    @State private var percentageSelected: Double?

    init(vault: Vault) {
        _viewModel = StateObject(wrappedValue: CircleDepositViewModel(vault: vault))
    }

    var body: some View {
        ZStack {
            if let coinMeta = viewModel.coinMeta {
                AmountFunctionTransactionScreen(
                    title: "circleDepositTitle".localized,
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

    func handleVerify() async {
        guard let immutableTx = await viewModel.makeTransaction() else { return }
        await MainActor.run {
            router.navigate(to: SendRoute.verify(tx: immutableTx, retrySignal: SendRetrySignal(), vault: viewModel.vault))
        }
    }
}
