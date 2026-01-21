//
//  WithdrawRewardsTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct WithdrawRewardsTransactionScreen: View {
    @StateObject var viewModel: WithdrawRewardsTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    var body: some View {
        AmountFunctionTransactionScreen(
            title: String(format: "withdrawRewards".localized, viewModel.coin.ticker),
            coin: viewModel.rewardsCoin,
            availableAmount: viewModel.rewards,
            percentageSelected: $viewModel.percentageSelected,
            percentageFieldType: .slider,
            amountField: viewModel.amountField,
            validForm: $viewModel.validForm
        ) {
            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            onVerify(transactionBuilder)
        } customView: {
            EmptyView()
        }
        .onLoad { viewModel.onLoad() }
        .onChange(of: viewModel.percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
    }
}

#Preview {
    WithdrawRewardsTransactionScreen(
        viewModel: WithdrawRewardsTransactionViewModel(
            coin: .example,
            vault: .example,
            rewards: .zero,
            rewardsCoin: .example
        )
    ) { _ in }
}
