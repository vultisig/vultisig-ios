//
//  MintTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct MintTransactionScreen: View {
    @StateObject var viewModel: MintTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    var body: some View {
        AmountFunctionTransactionScreen(
            title: String(format: "mintCoin".localized, viewModel.yCoin.ticker),
            coin: viewModel.coin.toCoinMeta(),
            availableAmount: viewModel.coin.balanceDecimal,
            percentageSelected: $viewModel.percentageSelected,
            percentageFieldType: .button,
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
    MintTransactionScreen(
        viewModel: MintTransactionViewModel(
            coin: .example,
            yCoin: .example,
            vault: .example
        )
    ) { _ in }
}
