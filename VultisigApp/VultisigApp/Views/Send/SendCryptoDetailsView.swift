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
    @ObservedObject var sendDetailsViewModel: SendDetailsViewModel
    let vault: Vault
    @Binding var settingsPresented: Bool
    
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
        .onFirstAppear {
            setData()
        }
        .onChange(of: tx.coin) { oldValue, newValue in
            setData()
        }
        .alert(isPresented: $sendCryptoViewModel.showAlert) {
            alert
        }
        .navigationDestination(isPresented: $isCoinPickerActive) {
            CoinPickerView(coins: sendCryptoViewModel.pickerCoins(vault: vault, tx: tx)) { coin in
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
    
    var button: some View {
        Button {
            Task{
                await validateForm()
            }
        } label: {
            HStack {
                FilledButton(
                    title: sendCryptoViewModel.isLoading ? "loadingDetails" : "continue",
                    textColor: sendCryptoViewModel.isLoading ? .textDisabled : .blue600,
                    background: sendCryptoViewModel.isLoading ? .buttonDisabled : .turquoise600,
                    showLoader: sendCryptoViewModel.isLoading
                )
            }
        }
        .padding(.top, 20)
        .disabled(sendCryptoViewModel.isLoading)
    }
    
    var tabs: some View {
        ScrollView {
            VStack(spacing: 12) {
                SendDetailsAssetTab(
                    isExpanded: sendDetailsViewModel.selectedTab == .Asset,
                    tx: tx,
                    viewModel: sendDetailsViewModel,
                    sendCryptoViewModel: sendCryptoViewModel
                )
                
                SendDetailsAddressTab(
                    isExpanded: sendDetailsViewModel.selectedTab == .Address,
                    tx: tx,
                    viewModel: sendDetailsViewModel,
                    sendCryptoViewModel: sendCryptoViewModel,
                    focusedField: $focusedField
                )
                
                SendDetailsAmountTab(
                    isExpanded: sendDetailsViewModel.selectedTab == .Amount,
                    tx: tx,
                    viewModel: sendDetailsViewModel,
                    sendCryptoViewModel: sendCryptoViewModel,
                    validateForm: validateForm,
                    focusedField: $focusedField,
                    settingsPresented: $settingsPresented
                )
            }
            .padding(16)
        }
    }
    
    func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(leadingText)
            Spacer()
            Text(trailingText)
        }
        .font(.body14MenloBold)
        .foregroundColor(.neutral0)
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
            .font(.body12MenloBold)
            .foregroundColor(.neutral0)
            .padding(.vertical, 6)
            .padding(.horizontal, 20)
            .background(Color.blue600)
            .cornerRadius(6)
    }
    
    func validateForm() async {
        sendDetailsViewModel.selectedTab = .Amount
        sendCryptoViewModel.validateAmount(amount: tx.amount.description)
        
        if await sendCryptoViewModel.validateForm(tx: tx) {
            sendCryptoViewModel.moveToNextView()
            sendCryptoViewModel.isLoading = false
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
        sendDetailsViewModel: SendDetailsViewModel(),
        vault: Vault.example,
        settingsPresented: .constant(false)
    )
}
