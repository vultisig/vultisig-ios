//
//  SendCryptoDetailsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import OSLog
import SwiftUI

enum Field: Hashable {
    case toAddress
    case amount
    case amountInUSD
}

struct SendCryptoDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @ObservedObject var coinViewModel: CoinViewModel
    let group: GroupedChain
    
    @State var toAddress = ""
    @State var amount = ""
    
    @FocusState private var focusedField: Field?
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
        .alert(isPresented: $sendCryptoViewModel.showAlert) {
            alert
        }
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(sendCryptoViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                coinSelector
                fromField
                toField
                amountField
                amountUSDField
                gasField
            }
            .padding(.horizontal, 16)
        }
    }
    
    var coinSelector: some View {
        TokenSelectorDropdown(coins: .constant(group.coins), selected: $tx.coin)
    }
    
    var fromField: some View {
        VStack(spacing: 8) {
            getTitle(for: "from")
            fromTextField
        }
    }
    
    var fromTextField: some View {
        Text(tx.fromAddress)
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.blue600)
            .cornerRadius(10)
            .lineLimit(1)
    }
    
    var toField: some View {
        VStack(spacing: 8) {
            getTitle(for: "to")
            SendCryptoAddressTextField(tx: tx, sendCryptoViewModel: sendCryptoViewModel)
                .focused($focusedField, equals: .toAddress)
        }
    }
    
    var amountField: some View {
        VStack(spacing: 8) {
            getTitle(for: "amount")
            textField
        }
    }
    
    var textField: some View {
        SendCryptoAmountTextField(
            amount: $tx.amount,
            onChange: { await sendCryptoViewModel.convertToUSD(newValue: $0, tx: tx) },
            onMaxPressed: { sendCryptoViewModel.setMaxValues(tx: tx) }
        )
        .focused($focusedField, equals: .amount)
    }
    
    var amountUSDField: some View {
        VStack(spacing: 8) {
            getTitle(for: "amount(inUSD)")
            textFieldUSD
        }
    }
    
    var textFieldUSD: some View {
        SendCryptoAmountTextField(
            amount: $tx.amountInUSD,
            onChange: { await sendCryptoViewModel.convertUSDToCoin(newValue: $0, tx: tx) }
        )
        .focused($focusedField, equals: .amountInUSD)
    }
    
    var gasField: some View {
        HStack {
            Text(NSLocalizedString("gas(auto)", comment: ""))
            Spacer()
			Text("\(tx.gas) \(tx.coin.feeUnit )")
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
    }
    
    var button: some View {
        Button {
            validateForm()
        } label: {
            FilledButton(title: "continue")
        }
        .padding(40)
    }
    
    private func getTitle(for text: String) -> some View {
        Text(
            NSLocalizedString(text, comment: "")
                .replacingOccurrences(of: "USD", with: SettingsViewModel.shared.selectedCurrency.description().uppercased())
        )
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func validateForm() {
        if sendCryptoViewModel.validateForm(tx: tx) {
            sendCryptoViewModel.moveToNextView()
        }
    }
}

#Preview {
    SendCryptoDetailsView(
        tx: SendTransaction(),
        sendCryptoViewModel: SendCryptoViewModel(),
        coinViewModel: CoinViewModel(),
        group: GroupedChain.example
    )
}
