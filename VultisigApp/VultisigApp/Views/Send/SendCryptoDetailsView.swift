//
//  SendCryptoDetailsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import OSLog
import SwiftUI

enum Field: Int, Hashable {
    case toAddress
    case amount
    case amountInFiat
    case memo
}

struct SendCryptoDetailsView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    let vault: Vault
    
    @State var amount = ""
    @State var nativeTokenBalance = ""
    @State var coinBalance: String? = nil
    @State var showMemoField = false
    
    @State var isCoinPickerActive = false
    
    @StateObject var keyboardObserver = KeyboardObserver()
    
    @FocusState var focusedField: Field?
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
        .onAppear {
            setData()
        }
        .onChange(of: tx.coin) { oldValue, newValue in
            setData()
        }
        .alert(isPresented: $sendCryptoViewModel.showAlert) {
            alert
        }
        .navigationDestination(isPresented: $isCoinPickerActive) {
            CoinPickerView(coins: vault.coins) { coin in
                tx.coin = coin
                tx.fromAddress = coin.address
            }
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(sendCryptoViewModel.errorTitle, comment: "")),
            message: Text(NSLocalizedString(sendCryptoViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }

    var coinSelector: some View {
        TokenSelectorDropdown(
            coin: tx.coin,
            onPress: {
                isCoinPickerActive = true
            }
        )
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
                .id(Field.toAddress)
                .onSubmit {
                    focusNextField($focusedField)
                }
        }
    }
    
    var memoField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    showMemoField.toggle()
                }
            } label: {
                memoFieldTitle
            }
            
            MemoTextField(memo: $tx.memo)
                .focused($focusedField, equals: .memo)
                .id(Field.memo)
                .onSubmit {
                    focusNextField($focusedField)
                }
                .frame(height: showMemoField ? nil : 0, alignment: .top)
                .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var memoFieldTitle: some View {
        HStack(spacing: 8) {
            getTitle(for: "memo(optional)", isExpanded: false)
            
            Image(systemName: showMemoField ? "chevron.up" : "chevron.down")
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var percentageButtons: some View {
        HStack(spacing: 12) {
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx, percentage: 25)
            } label: {
                getPercentageCell(for: "25")
            }
            
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx, percentage: 50)
            } label: {
                getPercentageCell(for: "50")
            }
        }
    }
    
    var amountField: some View {
        VStack(spacing: 8) {
            HStack {
                getTitle(for: "amount")
                Spacer()
                percentageButtons
            }
            
            textField
        }
    }
    
    var textField: some View {
        SendCryptoAmountTextField(
            amount: $tx.amount,
            onChange: {
                await sendCryptoViewModel.convertToFiat(newValue: $0, tx: tx)
            },
            onMaxPressed: { sendCryptoViewModel.setMaxValues(tx: tx) }
        )
        .focused($focusedField, equals: .amount)
        .id(Field.amount)
        .onChange(of: tx.coin) { oldValue, newValue in
            Task {
                await sendCryptoViewModel.convertToFiat(newValue: tx.amount, tx: tx)
            }
        }
    }
    
    var existentialDepositTextMessage: some View {
        HStack {
            Text(NSLocalizedString("polkadotExistentialDepositError", comment: ""))
        }
        .font(.body8Menlo)
        .foregroundColor(.red)
    }
    
    var balanceNativeTokenField: some View {
        HStack {
            Text(NSLocalizedString("balanceNativeToken", comment: ""))
            Spacer()
            Text(nativeTokenBalance)
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .onAppear{
            Task {
                let balanceInt = await tx.getNativeTokenBalance()
                nativeTokenBalance = balanceInt.description
            }
        }
    }
    
    var amountFiatField: some View {
        VStack(spacing: 8) {
            getTitle(for: "amount(inFiat)")
            textFiatField
        }
    }
    
    var textFiatField: some View {
        SendCryptoAmountTextField(
            amount: $tx.amountInFiat,
            onChange: { await sendCryptoViewModel.convertFiatToCoin(newValue: $0, tx: tx) }
        )
        .focused($focusedField, equals: .amountInFiat)
        .id(Field.amountInFiat)
    }

    func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(leadingText)
            Spacer()
            Text(trailingText)
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
    }

    var button: some View {
        Button {
            Task{
                await validateForm()
            }
        } label: {
            FilledButton(title: "continue")
        }
        .padding(40)
    }
    
    private func getTitle(for text: String, isExpanded: Bool = true) -> some View {
        Text(
            NSLocalizedString(text, comment: "")
                .replacingOccurrences(of: "Fiat", with: SettingsCurrency.current.rawValue)
        )
        .font(.body14MontserratMedium)
        .foregroundColor(.neutral0)
        .frame(maxWidth: isExpanded ? .infinity : nil, alignment: .leading)
    }
    
    private func getPercentageCell(for text: String) -> some View {
        Text(text + "%")
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .padding(.vertical, 6)
            .padding(.horizontal, 20)
            .background(Color.blue600)
            .cornerRadius(6)
    }
    
    private func validateForm() async {
        sendCryptoViewModel.validateAmount(amount: tx.amount.description)
        if await sendCryptoViewModel.validateForm(tx: tx) {
            sendCryptoViewModel.moveToNextView()
        }
    }
    
    func getBalance() async {
        await BalanceService.shared.updateBalance(for: tx.coin)
        coinBalance = tx.coin.balanceString
    }
}

#Preview {
    SendCryptoDetailsView(
        tx: SendTransaction(),
        sendCryptoViewModel: SendCryptoViewModel(),
        vault: Vault.example
    )
}
