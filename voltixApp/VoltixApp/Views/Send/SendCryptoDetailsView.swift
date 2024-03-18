//
//  SendCryptoDetailsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import OSLog
import SwiftUI

struct SendCryptoDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @ObservedObject var coinViewModel: CoinViewModel
    let group: GroupedChain
    
    @State var toAddress = ""
    @State var amount = ""
    
    let logger = Logger(subsystem: "send-input-details", category: "transaction")
    
    var body: some View {
        ZStack {
            background
            view
        }
        .gesture(DragGesture())
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                coinSelector
                fromField
                toField
                amountField
                gasField
            }
            .padding(.horizontal, 16)
        }
    }
    
    var coinSelector: some View {
        TokenSelectorDropdown(tx: tx, coinViewModel: coinViewModel, group: group)
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
            AddressTextField(tx: tx, logger: logger)
        }
    }
    
    var amountField: some View {
        VStack(spacing: 8) {
            getTitle(for: "amount")
            AmountTextField(amount: $amount)
        }
    }
    
    var gasField: some View {
        HStack {
            Text(NSLocalizedString("gas(auto)", comment: ""))
            Spacer()
            Text(tx.gas)
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
    }
    
    var button: some View {
        Button {
            sendCryptoViewModel.moveToNextView()
        } label: {
            FilledButton(title: "continue")
        }
        .padding(40)
    }
    
    private func getTitle(for text: String) -> some View {
        Text(NSLocalizedString(text, comment: ""))
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SendCryptoDetailsView(tx: SendTransaction(), sendCryptoViewModel: SendCryptoViewModel(), coinViewModel: CoinViewModel(), group: GroupedChain.example)
}
