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
            sendDetailsViewModel.onLoad()
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
        PrimaryButton(
            title: sendCryptoViewModel.isLoading ? "loadingDetails" : "continue",
            isLoading: sendCryptoViewModel.isLoading
        ) {
            Task{
                await validateForm()
            }
        }
        .padding(.top, 20)
        .disabled(sendCryptoViewModel.isLoading)
    }
    
    var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    SendDetailsAssetTab(
                        isExpanded: sendDetailsViewModel.selectedTab == .asset,
                        tx: tx,
                        viewModel: sendDetailsViewModel,
                        sendCryptoViewModel: sendCryptoViewModel
                    )
                    .id(SendDetailsFocusedTab.asset.rawValue)
                    
                    SendDetailsAddressTab(
                        isExpanded: sendDetailsViewModel.selectedTab == .address,
                        tx: tx,
                        viewModel: sendDetailsViewModel,
                        sendCryptoViewModel: sendCryptoViewModel,
                        focusedField: $focusedField
                    )
                    .id(SendDetailsFocusedTab.address.rawValue)
                    
                    SendDetailsAmountTab(
                        isExpanded: sendDetailsViewModel.selectedTab == .amount,
                        tx: tx,
                        viewModel: sendDetailsViewModel,
                        sendCryptoViewModel: sendCryptoViewModel,
                        validateForm: validateForm,
                        focusedField: $focusedField,
                        settingsPresented: $settingsPresented
                    )
                    .id(SendDetailsFocusedTab.amount.rawValue)
                }
                .padding(16)
            }
            .onChange(of: sendDetailsViewModel.selectedTab) { _, newValue in
                proxy.scrollTo(SendDetailsFocusedTab.asset.rawValue, anchor: .bottom)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut) {
                        proxy.scrollTo(newValue.rawValue, anchor: .top)
                    }
                }
            }
        
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
        await MainActor.run {
            sendCryptoViewModel.isLoading = true
        }
        
        sendDetailsViewModel.onSelect(tab: .amount)
        sendCryptoViewModel.validateAmount(amount: tx.amount.description)
        
        if await sendCryptoViewModel.validateForm(tx: tx) {
            sendCryptoViewModel.moveToNextView()
        }
        
        await MainActor.run {
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
