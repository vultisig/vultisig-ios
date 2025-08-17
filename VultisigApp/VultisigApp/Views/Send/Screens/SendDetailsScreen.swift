//
//  SendDetailsScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import OSLog
import SwiftUI
import BigInt

enum Field: Int, Hashable {
    case toAddress
    case amount
    case amountInFiat
    case memo
}

struct SendDetailsScreen: View {
    @State var coin: Coin?
    @State var selectedChain: Chain? = nil
    @ObservedObject var tx: SendTransaction
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @StateObject var sendDetailsViewModel: SendDetailsViewModel
    let vault: Vault
    @State var settingsPresented: Bool = false
    
    @State var amount = ""
    @State var nativeTokenBalance = ""
    @State var coinBalance: String? = nil
    @State var showMemoField = false
    
    @State var isCoinPickerActive = false
    
    @StateObject var keyboardObserver = KeyboardObserver()
    
    @FocusState var focusedField: Field?
    @State var scrollProxy: ScrollViewProxy?
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @State var navigateToVerify: Bool = false
    
    var body: some View {
        Screen(title: "send".localized) {
            container
        }
        .disabled(sendCryptoViewModel.showLoader)
        .overlay(sendCryptoViewModel.showLoader ? Loader() : nil)
        .onLoad {
            Task {
                await setMainData()
                await loadGasInfo()
            }
            sendDetailsViewModel.onLoad()
            setData()
        }
        .onChange(of: tx.coin) {
            Task {
                await loadGasInfo()
            }
        }
        .onDisappear {
            sendCryptoViewModel.stopMediator()
        }
        .sheet(isPresented: $settingsPresented) {
            SendGasSettingsView(
                viewModel: SendGasSettingsViewModel(
                    coin: tx.coin,
                    vault: vault,
                    gasLimit: tx.gasLimit,
                    customByteFee: tx.customByteFee,
                    selectedMode: tx.feeMode
                ),
                output: self
            )
        }
        .navigationDestination(isPresented: $navigateToVerify) {
            SendRouteBuilder().buildVerifyScreen(tx: tx, vault: vault)
        }
    }
    
    var content: some View {
        view
            .onChange(of: tx.coin) { oldValue, newValue in
                print("Coin changed", newValue)
                setData()
            }
            .onChange(of: focusedField) { _, focusedField in
                onChange(focusedField: focusedField)
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
        .disabled(sendCryptoViewModel.continueButtonDisabled)
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
            }
            .refreshable {
                await onRefresh()
            }
            .onLoad {
                scrollProxy = proxy
            }
            .onChange(of: sendDetailsViewModel.selectedTab) { oldValue, newValue in
                handleScroll(newValue: newValue, oldValue: oldValue)
            }
        }
    }
    
    var chainPicker: some View {
        SwapChainPickerView(
            vault: vault,
            showSheet: $sendDetailsViewModel.showChainPickerSheet,
            selectedChain: $sendDetailsViewModel.selectedChain
        )
    }

    var coinPicker: some View {
        SwapCoinPickerView(
            vault: vault,
            showSheet: $sendDetailsViewModel.showCoinPickerSheet,
            selectedCoin: $tx.coin,
            selectedChain: sendDetailsViewModel.selectedChain
        )
    }
    
    func onChange(focusedField: Field?) {
        if focusedField == .toAddress {
            handleScroll(newValue: .address, oldValue: .asset, delay: 0.2)
        }
    }
    
    func handleScroll(newValue: SendDetailsFocusedTab?, oldValue: SendDetailsFocusedTab?, delay: Double = 0.7) {
        // This delay is necessary when the screen starts
        DispatchQueue.main.asyncAfter(deadline: .now() + (oldValue == nil ? 0.2 : 0)) {
            scrollProxy?.scrollTo(SendDetailsFocusedTab.amount.rawValue, anchor: .top)
            
            // If it's .amount, there is no need to scroll again
            guard newValue != .amount else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut) {
                    scrollProxy?.scrollTo(newValue?.rawValue, anchor: .top)
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
        .font(Theme.fonts.bodySMedium)
        .foregroundColor(Theme.colors.textPrimary)
    }

    private func getTitle(for text: String, isExpanded: Bool = true) -> some View {
        Text(
            NSLocalizedString(text, comment: "")
                .replacingOccurrences(of: "Fiat", with: SettingsCurrency.current.rawValue)
        )
        .font(Theme.fonts.bodySMedium)
        .foregroundColor(Theme.colors.textPrimary)
        .frame(maxWidth: isExpanded ? .infinity : nil, alignment: .leading)
    }
    
    private func getPercentageCell(for text: String) -> some View {
        Text(text + "%")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 20)
            .background(Theme.colors.bgSecondary)
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
                sendCryptoViewModel.isValidatingForm = true
            }
            sendCryptoViewModel.validateAmount(amount: tx.amount.description)
            
            if await sendCryptoViewModel.validateForm(tx: tx) {
                await MainActor.run {
                    navigateToVerify = true
                }
            }
        }
        
        await MainActor.run {
            sendCryptoViewModel.isValidatingForm = false
        }
    }
    
    func getBalance() async {
        await BalanceService.shared.updateBalance(for: tx.coin)
        if Task.isCancelled { return }
        await MainActor.run {
            coinBalance = tx.coin.balanceString
        }
    }

    private func onRefresh() async {
        async let gas: Void = sendCryptoViewModel.loadGasInfoForSending(tx: tx)
        async let bal: Void = BalanceService.shared.updateBalance(for: tx.coin)
        _ = await (gas, bal)
        if Task.isCancelled { return }
        await MainActor.run {
            coinBalance = tx.coin.balanceString
        }
    }
}

extension SendDetailsScreen: SendGasSettingsOutput {

    func didSetFeeSettings(chain: Chain, mode: FeeMode, gasLimit: BigInt?, byteFee: BigInt?) {
        switch chain.chainType {
        case .EVM:
            tx.customGasLimit = gasLimit
        case .UTXO:
            tx.customByteFee = byteFee
        default:
            return
        }

        tx.feeMode = mode

        Task {
            await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
        }
    }
}

extension SendDetailsScreen {
    private func setMainData() async {
        guard !sendCryptoViewModel.isLoading else { return }
        
        if let coin = coin {
            tx.coin = coin
            tx.fromAddress = coin.address
            tx.toAddress = deeplinkViewModel.address ?? ""
            self.coin = nil
            selectedChain = coin.chain
        }
        
        DebounceHelper.shared.debounce {
            validateAddress(deeplinkViewModel.address ?? "")
        }
        
        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
    }
    
    private func loadGasInfo() async {
        guard !sendCryptoViewModel.isLoading else { return }
        await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
    }
    
    private func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
}

#Preview {
    SendDetailsScreen(
        coin: .example,
        tx: SendTransaction(),
        sendDetailsViewModel: SendDetailsViewModel(),
        vault: Vault.example
    )
}
