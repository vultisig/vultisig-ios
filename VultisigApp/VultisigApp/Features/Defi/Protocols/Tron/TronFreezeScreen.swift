//
//  TronFreezeScreen.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct TronFreezeScreen: View {
    @StateObject var viewModel: TronFreezeViewModel
    @Environment(\.router) var router

    init(vault: Vault) {
        self._viewModel = StateObject(wrappedValue: TronFreezeViewModel(vault: vault))
    }

    var body: some View {
        content
            .task { await viewModel.loadBalance() }
    }

    @ViewBuilder
    var content: some View {
        if let coin = viewModel.trxCoin {
            AmountFunctionTransactionScreen(
                title: "tronFreezeTitle".localized,
                coin: coin.toCoinMeta(),
                availableAmount: viewModel.availableBalance,
                percentageSelected: $viewModel.percentageSelected,
                percentageFieldType: .button,
                amountField: viewModel.amountField,
                validForm: $viewModel.validForm,
                onVerify: onVerify,
                customView: { EmptyView() },
                topView: { TronResourceTypeToggle(selection: $viewModel.selectedResourceType) }
            )
            .onLoad { viewModel.onLoad() }
        } else {
            TronMissingTrxView()
        }
    }

    private func onVerify() {
        guard let tx = viewModel.makeTransaction() else { return }
        router.navigate(to: SendRoute.verify(tx: tx, retrySignal: SendRetrySignal(), vault: viewModel.vault))
    }
}
