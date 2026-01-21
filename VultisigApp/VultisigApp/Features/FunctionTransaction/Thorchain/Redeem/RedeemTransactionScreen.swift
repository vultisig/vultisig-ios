//
//  RedeemTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct RedeemTransactionScreen: View {
    @StateObject var viewModel: RedeemTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    var body: some View {
        AmountFunctionTransactionScreen(
            title: String(format: "redeemCoin".localized, viewModel.coin.ticker),
            coin: viewModel.yCoin.toCoinMeta(),
            availableAmount: viewModel.yCoin.balanceDecimal,
            percentageSelected: $viewModel.percentageSelected,
            percentageFieldType: .slider,
            amountField: viewModel.amountField,
            validForm: $viewModel.validForm,
            customViewPosition: .bottom
        ) {
            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            onVerify(transactionBuilder)
        } customView: {
            slippageView
        }
        .onLoad { viewModel.onLoad() }
        .onChange(of: viewModel.percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
    }

    var slippageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\("slippage".localized):")
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
            PercentageButtonsStack(percentages: [1, 2, 5, 7.5], selectedPercentage: $viewModel.slippage)
        }
    }
}

#Preview {
    RedeemTransactionScreen(
        viewModel: RedeemTransactionViewModel(
            yCoin: .example,
            coin: .example,
            vault: .example
        )
    ) { _ in }
}
