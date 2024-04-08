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
        
        } label: {
            FilledButton(title: "sign")
        }
        .padding(40)
    }

    func getFromAmount() -> String {
        return "\(tx.fromAmount) \(tx.fromCoin.ticker)"
    }

    func getToAmount() -> String {
        return "\(tx.toAmount) \(tx.toCoin.ticker)"
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
}
