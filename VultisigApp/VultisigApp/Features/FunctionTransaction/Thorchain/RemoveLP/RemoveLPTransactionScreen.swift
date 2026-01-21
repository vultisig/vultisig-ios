//
//  RemoveLPTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct RemoveLPTransactionScreen: View {
    enum FocusedField {
        case amount
    }

    @StateObject var viewModel: RemoveLPTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        FormScreen(
            title: String(format: "removeCoinLP".localized, viewModel.position.coin1.chain.name),
            validForm: $viewModel.validForm,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: "amount".localized,
                isValid: viewModel.validForm,
                value: .empty,
                showValue: false,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount,
            ) { _ in
            } content: {
                VStack(spacing: 16) {
                    RemoveLPAmountSection(
                        percentage: $viewModel.percentageSelected,
                        position: viewModel.position
                    )

                    if let feeError = viewModel.feeError {
                        InfoBannerView(description: feeError, type: .error, leadingIcon: "triangle-alert")
                    }
                }
            }
        }
        .onLoad {
            focusedFieldBinding = .amount
            viewModel.onLoad()
        }
    }

    func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}

private struct RemoveLPAmountSection: View {
    @Binding var percentage: Double?
    let position: LPPosition

    var formattedPercentage: Double { percentage ?? 100 }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            amountView(for: position.coin1, balance: position.coin1Amount)
            Separator(color: Theme.colors.borderLight, opacity: 1)
            amountView(for: position.coin2, balance: position.coin2Amount)
            Spacer()
            PercentageSliderView(percentage: $percentage, minimumValue: 1)
        }
    }

    @ViewBuilder
    func amountView(for coin: CoinMeta, balance: Decimal) -> some View {
        let percentageAmount = balance * Decimal(formattedPercentage / 100)
        let amount = AmountFormatter.formatCryptoAmount(value: percentageAmount, coin: coin)

        VStack(spacing: 5) {
            Text(amount)
                .font(Theme.fonts.largeTitle)
                .foregroundStyle(Theme.colors.textPrimary)
            Text((Double(formattedPercentage) / 100).formatted(.percent))
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }
}

#Preview {
    RemoveLPTransactionScreen(
        viewModel: RemoveLPTransactionViewModel(
            coin: .example,
            vault: .example,
            position: .init(
                coin1: .example,
                coin1Amount: .zero,
                coin2: .example,
                coin2Amount: .zero,
                poolName: "AVAX.AVAX",
                poolUnits: "88607976046443",
                apr: .zero,
                vault: .example
            )
        )
    ) { _ in }
}
