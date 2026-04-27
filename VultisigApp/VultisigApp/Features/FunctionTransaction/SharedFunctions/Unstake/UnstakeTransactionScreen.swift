//
//  UnstakeTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct UnstakeTransactionScreen: View {
    @StateObject var viewModel: UnstakeTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    var body: some View {
        AmountFunctionTransactionScreen(
            title: String(format: "unstakeCoin".localized, viewModel.coin.ticker),
            coin: viewModel.coin.toCoinMeta(),
            availableAmount: viewModel.availableAmount,
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
    UnstakeTransactionScreen(
        viewModel: UnstakeTransactionViewModel(
            coin: .example,
            vault: .example,
            isAutocompound: false
        )
    ) { _ in }
}
