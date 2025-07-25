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
            .onChange(of: sendDetailsViewModel.selectedTab) { oldValue, newValue in
                handleScroll(proxy: proxy, newValue: newValue, oldValue: oldValue)
            }
        }
    }
    
    func handleScroll(proxy: ScrollViewProxy, newValue: SendDetailsFocusedTab?, oldValue: SendDetailsFocusedTab?) {
        // This delay is necessary when the screen starts
        DispatchQueue.main.asyncAfter(deadline: .now() + (oldValue == nil ? 0.2 : 0)) {
            proxy.scrollTo(SendDetailsFocusedTab.amount.rawValue, anchor: .top)
            
            // If it's .amount, there is no need to scroll again
            guard newValue != .amount else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeInOut) {
                    proxy.scrollTo(newValue?.rawValue, anchor: .top)
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
        switch sendDetailsViewModel.selectedTab {
        case .none:
            sendDetailsViewModel.onSelect(tab: .asset)
            return
        case .asset:
            sendDetailsViewModel.onSelect(tab: .address)
            return
        case .address:
            sendDetailsViewModel.onSelect(tab: .amount)
            return
        case .amount:
            await MainActor.run {
                sendCryptoViewModel.isLoading = true
            }
            sendCryptoViewModel.validateAmount(amount: tx.amount.description)
            
            if await sendCryptoViewModel.validateForm(tx: tx) {
                sendCryptoViewModel.moveToNextView()
            }
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
