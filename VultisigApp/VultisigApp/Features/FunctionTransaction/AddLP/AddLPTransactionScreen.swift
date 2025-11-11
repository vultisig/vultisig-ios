//
//  AddLPTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct AddLPTransactionScreen: View {
    @StateObject var viewModel: AddLPTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void
    
    var body: some View {
        AmountFunctionTransactionScreen(
            title: String(format: "addCoinLP".localized, viewModel.coin.chain.name),
            coin: viewModel.coin.toCoinMeta(),
            availableAmount: viewModel.coin.balanceDecimal,
            percentageSelected: $viewModel.percentageSelected,
            percentageFieldType: .button,
            amountField: viewModel.amountField,
            validForm: $viewModel.validForm,
            customViewPosition: .bottom
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
    AddLPTransactionScreen(
        viewModel: AddLPTransactionViewModel(
            coin: .example,
            coin2: .example,
            vault: .example,
            position: .init(
                coin1: .example,
                coin1Amount: .zero,
                coin2: .example,
                coin2Amount: .zero,
                poolName: "AVAX.AVAX",
                apr: .zero,
                vault: .example
            )
        )
    ) { _ in }
}
