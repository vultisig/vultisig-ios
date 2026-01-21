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
            VStack(spacing: 12) {
                autocompoundToggle
                gasReservationInfo
            }
        }
        .onLoad { viewModel.onLoad() }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
    }

    @ViewBuilder
    var autocompoundToggle: some View {
        if viewModel.supportsAutocompound {
            AutocompoundToggle(isEnabled: $viewModel.isAutocompound)
        }
    }

    @ViewBuilder
    var gasReservationInfo: some View {
        if let message = viewModel.gasReservationMessage {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
                Text(message)
                    .font(Theme.fonts.caption12)
                    .foregroundColor(Theme.colors.textTertiary)
                Spacer()
            }
            .padding(12)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(8)
        }
    }
}

#Preview {
    StakeTransactionScreen(
        viewModel: StakeTransactionViewModel(
            coin: .example,
            vault: .example,
            defaultAutocompound: false
        )
    ) { _ in }
}
