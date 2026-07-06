//
//  TronUnfreezeScreen.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct TronUnfreezeScreen: View {
    @StateObject private var viewModel: TronUnfreezeViewModel
    @Environment(\.router) var router

    init(vault: Vault, frozenBandwidthBalance: Decimal, frozenEnergyBalance: Decimal) {
        self._viewModel = StateObject(
            wrappedValue: TronUnfreezeViewModel(
                vault: vault,
                frozenBandwidthBalance: frozenBandwidthBalance,
                frozenEnergyBalance: frozenEnergyBalance
            )
        )
    }

    var body: some View {
        content
            .task { await viewModel.loadData() }
    }

    @ViewBuilder
    var content: some View {
        if let coin = viewModel.trxCoin {
            AmountFunctionTransactionScreen(
                title: "tronUnfreezeTitle".localized,
                coin: coin.toCoinMeta(),
                availableAmount: viewModel.availableAmount,
                percentageSelected: $viewModel.percentageSelected,
                percentageFieldType: .slider,
                amountField: viewModel.amountField,
                validForm: $viewModel.validForm,
                onVerify: onVerify,
                customView: { EmptyView() },
                topView: {
                    TronResourceTypeToggle(
                        selection: $viewModel.selectedResourceType,
                        onChange: { viewModel.onResourceChange() }
                    )
                }
            )
            .onLoad { viewModel.onLoad() }
        } else {
            TronMissingTrxScreen()
        }
    }

    private func onVerify() {
        guard let tx = viewModel.makeTransaction() else { return }
        router.navigate(to: SendRoute.verify(tx: tx, retrySignal: SendRetrySignal(), vault: viewModel.vault))
    }
}
