//
//  SwapVerifyView.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import SwiftUI

struct SwapVerifyView: View {

    @StateObject var verifyViewModel = SwapCryptoVerifyViewModel()

    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel

    var body: some View {
        ZStack {
            Background()
            view
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
        .blur(radius: swapViewModel.isLoading ? 1 : 0)
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
            Separator()
            getDetailsCell(for: "gas", with: getGasAmount())
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }

    var checkboxes: some View {
        VStack(spacing: 16) {
            Checkbox(isChecked: $verifyViewModel.isAmountCorrect, text: "correctAmountCheck")
            Checkbox(isChecked: $verifyViewModel.isHackedOrPhished, text: "notHackedCheck")
        }
    }

    var button: some View {
        Button {
            Task {
                if await swapViewModel.buildKeysignPayload(tx: tx) {
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
        return "\(tx.toAmount) \(tx.toCoin.ticker)"
    }

    private func getGasAmount() -> String {
        return tx.feeString
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
