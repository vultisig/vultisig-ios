//
//  SwapVerifyView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import SwiftUI

struct SwapVerifyView: View {

    @StateObject var verifyViewModel = SwapCryptoVerifyViewModel()

    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel
    let vault: Vault

    var body: some View {
        ZStack {
            Background()
            view

            if swapViewModel.isLoading {
                Loader()
            }
        }
        .onDisappear {
            swapViewModel.isLoading = false
        }
    }

    var view: some View {
        VStack {
            fields
            button
        }
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                summary
                checkboxes
            }
            .padding(.horizontal, 16)
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            getValueCell(for: "from", with: getFromAmount())
            Separator()
            getValueCell(for: "to", with: getToAmount())
            if swapViewModel.showAllowance(tx: tx) {
                Separator()
                getValueCell(for: "ERC20 Allowance", with: "UNLIMITED")
            }
            if swapViewModel.showDuration(tx: tx) {
                Separator()
                getDetailsCell(for: "Estimated Fees", with: swapViewModel.swapFeeString(tx: tx))
            }
            if swapViewModel.showFees(tx: tx) {
                Separator()
                getDetailsCell(for: "Estimated Time", with: swapViewModel.durationString(tx: tx))
            }
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }

    var checkboxes: some View {
        VStack(spacing: 16) {
            Checkbox(isChecked: $verifyViewModel.isAmountCorrect, text: "The swap amount is correct")
            Checkbox(isChecked: $verifyViewModel.isFeeCorrect, text: "I agree with the amount I will receive after the swap.")
        }
    }

    var button: some View {
        Button {
            Task {
                if await swapViewModel.buildSwapKeysignPayload(tx: tx, vault: vault) {
                    swapViewModel.moveToNextView()
                }
            }
        } label: {
            FilledButton(title: "sign")
        }
        .disabled(!verifyViewModel.isValidForm)
        .opacity(verifyViewModel.isValidForm ? 1 : 0.5)
        .padding(40)
    }

    func getFromAmount() -> String {
        return "\(tx.fromAmount) \(tx.fromCoin.ticker)"
    }

    func getToAmount() -> String {
        return "\(tx.toAmountDecimal.description) \(tx.toCoin.ticker)"
    }

    func getValueCell(for title: String, with value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)

            Text(value)
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getDetailsCell(for title: String, with value: String) -> some View {
        HStack {
            Text(
                NSLocalizedString(title, comment: "")
                    .replacingOccurrences(of: "Fiat", with: SettingsCurrency.current.rawValue)
            )
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
    }
}
