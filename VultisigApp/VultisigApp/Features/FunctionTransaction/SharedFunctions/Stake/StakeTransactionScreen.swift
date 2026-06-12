//
//  StakeTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct StakeTransactionScreen: View {
    @StateObject var viewModel: StakeTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State var percentageSelected: Double?

    var body: some View {
        AmountFunctionTransactionScreen(
            title: String(format: "stakeCoin".localized, viewModel.coin.ticker),
            coin: viewModel.coin.toCoinMeta(),
            availableAmount: viewModel.maxStakeableAmount,
            percentageSelected: $percentageSelected,
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
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
    }
}

#Preview {
    StakeTransactionScreen(
        viewModel: StakeTransactionViewModel(
            coin: .example,
            vault: .example,
            isAutocompound: false
        )
    ) { _ in }
}
