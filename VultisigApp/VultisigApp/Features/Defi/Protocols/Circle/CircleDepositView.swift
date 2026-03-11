//
//  CircleDepositView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI

struct CircleDepositView: View {
    @StateObject var viewModel: CircleDepositViewModel
    @Environment(\.router) var router

    @State var percentageSelected: Double?

    init(vault: Vault) {
        _viewModel = StateObject(wrappedValue: CircleDepositViewModel(vault: vault))
    }

    var body: some View {
        Group {
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
        await viewModel.onContinue()
        await MainActor.run {
            router.navigate(to: SendRoute.verify(tx: viewModel.tx, vault: viewModel.vault))
        }
    }
}
