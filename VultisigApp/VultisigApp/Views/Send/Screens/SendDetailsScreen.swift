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

    @StateObject var keyboardObserver = KeyboardObserver()

    @FocusState var focusedField: Field?
    @State var scrollProxy: ScrollViewProxy?

    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @State var countdownTimer: Timer?

    @Environment(\.router) var router

    var body: some View {
        container
            .disabled(sendCryptoViewModel.showLoader)
            .overlay(sendCryptoViewModel.showLoader ? Loader() : nil)
            .onAppear {
                // Initialize button state immediately based on chain
                sendCryptoViewModel.initializePendingTransactionState(for: tx.coin.chain)
                Task {
                    await checkPendingTransactions()
                }
            }
            .onLoad {
                sendDetailsViewModel.onLoad()
                Task {
                    await setMainData()
                    // Fee calculation moved to Verify screen
                    await checkPendingTransactions()

                    // Start polling for current chain if there are pending transactions
                    PendingTransactionManager.shared.startPollingForChain(tx.coin.chain)
                }
                setData()
            }
            .onChange(of: tx.coin) { oldValue, newValue in
                // Initialize button state immediately for new chain
                sendCryptoViewModel.initializePendingTransactionState(for: newValue.chain)

                Task {
                    // SEMPRE para o polling da chain anterior
                    PendingTransactionManager.shared.stopPollingForChain(oldValue.chain)

                    // Fee calculation moved to Verify screen
                    await checkPendingTransactions()

                    // Só inicia polling se a NOVA chain suportar pending transactions
                    if newValue.chain.supportsPendingTransactions {
                        PendingTransactionManager.shared.startPollingForChain(newValue.chain)
                    }
                }
            }
            .onChange(of: tx.toAddress) { _, _ in
                validateAddress()
            }
            .onDisappear {
                sendCryptoViewModel.stopMediator()
                countdownTimer?.invalidate()

                // Stop all polling when leaving Send screen
                PendingTransactionManager.shared.stopAllPolling()
            }
            .crossPlatformSheet(isPresented: $settingsPresented) {
                SendGasSettingsView(
                    isPresented: $settingsPresented,
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
            .crossPlatformSheet(isPresented: $sendDetailsViewModel.showChainPickerSheet) {
                SwapChainPickerView(
                    vault: vault,
                    showSheet: $sendDetailsViewModel.showChainPickerSheet,
                    selectedChain: $sendDetailsViewModel.selectedChain
                )
                .environmentObject(coinSelectionViewModel)
            }
            .crossPlatformSheet(isPresented: $sendDetailsViewModel.showCoinPickerSheet) {
                SwapCoinPickerView(
                    vault: vault,
                    showSheet: $sendDetailsViewModel.showCoinPickerSheet,
                    selectedCoin: $tx.coin,
                    selectedChain: sendDetailsViewModel.selectedChain
                )
                .environmentObject(coinSelectionViewModel)
            }
    }

    var content: some View {
        view
            .onChange(of: tx.coin) { _, _ in
                setData()
            }
            .onChange(of: focusedField) { _, focusedField in
                onChange(focusedField: focusedField)
            }
            .alert(isPresented: $sendCryptoViewModel.showAlert) {
                alert
            }
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(sendCryptoViewModel.errorTitle, comment: "")),
            message: Text(NSLocalizedString(sendCryptoViewModel.errorMessage ?? .empty, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }

    var button: some View {
        PrimaryButton(
            title: getButtonTitle(),
            isLoading: sendCryptoViewModel.isLoading && !sendCryptoViewModel.hasPendingTransaction
        ) {
            Task {
                await validateForm()
            }
        }
        .disabled(getButtonDisabled())
    }

    private func getButtonDisabled() -> Bool {
        // Always disabled while loading normal operations
        if sendCryptoViewModel.continueButtonDisabled {
            return true
        }

        // Only check pending transactions for supported chains
        if tx.coin.chain.supportsPendingTransactions {
            // Disabled while checking for pending transactions (prevents flickering)
            if sendCryptoViewModel.isCheckingPendingTransactions {
                return true
            }

            // Disabled if there are confirmed pending transactions
            if sendCryptoViewModel.hasPendingTransaction {
                return true
            }
        }

        // For non-supported chains or no pending transactions, button is enabled
        return false
    }

    private func getButtonTitle() -> String {
        // Only show pending states for supported chains
        if tx.coin.chain.supportsPendingTransactions {
            if sendCryptoViewModel.isCheckingPendingTransactions {
                return "Checking pending transactions..."
            } else if sendCryptoViewModel.hasPendingTransaction {
                let elapsed = sendCryptoViewModel.pendingTransactionCountdown
                let minutes = elapsed / 60
                let seconds = elapsed % 60

                if minutes > 0 {
                    return "Pending transaction (\(minutes)m \(seconds)s)"
                } else {
                    return "Pending transaction (\(seconds)s)"
                }
            }
        }

        // Default states for all chains
        if sendCryptoViewModel.isLoading {
            return "loadingDetails"
        } else {
            return "continue"
        }
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

    func onChange(focusedField: Field?) {
        if focusedField == .toAddress {
            handleScroll(newValue: .address, oldValue: .asset, delay: 0.2)
        }
    }

    func handleScroll(newValue: SendDetailsFocusedTab?, oldValue: SendDetailsFocusedTab?, delay: Double = 0.7) {
        // This delay is necessary when the screen starts
        DispatchQueue.main.asyncAfter(deadline: .now() + (oldValue == nil ? 0.2 : 0)) {
            if newValue != .amount {
                withAnimation(.easeInOut) {
                    scrollProxy?.scrollTo(SendDetailsFocusedTab.amount.rawValue, anchor: .top)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut) {
                    scrollProxy?.scrollTo(newValue?.rawValue, anchor: .bottom)
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
            .background(Theme.colors.bgSurface1)
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
                    router.navigate(to: SendRoute.verify(tx: tx, vault: vault))
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
        // Fee calculation moved to Verify screen
        async let bal: Void = BalanceService.shared.updateBalance(for: tx.coin)
        async let pendingCheck: Void = PendingTransactionManager.shared.forceCheckPendingTransactions()
        _ = await (bal, pendingCheck)
        if Task.isCancelled { return }
        await MainActor.run {
            coinBalance = tx.coin.balanceString
        }
        await checkPendingTransactions()
    }
}

extension SendDetailsScreen: SendGasSettingsOutput {

    func didSetFeeSettings(chain: Chain, mode: FeeMode, gasLimit: BigInt?, byteFee: BigInt?) {
        switch chain.chainType {
        case .EVM:
            tx.customGasLimit = gasLimit
        case .UTXO, .Cardano:
            tx.customByteFee = byteFee
        default:
            return
        }

        tx.feeMode = mode
    }
}

extension SendDetailsScreen {
private func setMainData() async {
        guard !sendCryptoViewModel.isLoading else { return }

        if let coin = coin {
            // Store toAddress before reset if it's not empty
            let savedToAddress = tx.toAddress.isEmpty ? nil : tx.toAddress

            // Reset clears all state including fee
            tx.reset(coin: coin)

            // Restore or set toAddress
            if let saved = savedToAddress {
                tx.toAddress = saved
            } else if tx.toAddress.isEmpty {
                tx.toAddress = deeplinkViewModel.address ?? ""
            }

            deeplinkViewModel.address = nil
            self.coin = nil
            selectedChain = coin.chain
        } else {
            // Even if coin is nil, try to get address from deeplinkViewModel if tx.toAddress is empty
            if tx.toAddress.isEmpty, let deeplinkAddress = deeplinkViewModel.address {
                tx.toAddress = deeplinkAddress
                deeplinkViewModel.address = nil
            }
        }

        if !tx.toAddress.isEmpty {
            sendCryptoViewModel.validateAddress(tx: tx, address: tx.toAddress)
            validateAddress()
        }

        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
    }

    private func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }

    private func validateAddress() {
        Task {
            guard await sendCryptoViewModel.validateToAddress(tx: tx) else {
                sendDetailsViewModel.onSelect(tab: .address)
                return
            }
            sendDetailsViewModel.addressSetupDone = true
            sendDetailsViewModel.onSelect(tab: .amount)
        }
    }

    @MainActor
    private func checkPendingTransactions() async {
        guard tx.coin.chain.supportsPendingTransactions else {
            // For non-Cosmos chains, immediately enable button
            sendCryptoViewModel.hasPendingTransaction = false
            sendCryptoViewModel.pendingTransactionCountdown = 0
            sendCryptoViewModel.isCheckingPendingTransactions = false
            stopCountdownTimer()
            return
        }

        // Set checking state first for Cosmos chains
        sendCryptoViewModel.isCheckingPendingTransactions = true
        let pendingTxManager = PendingTransactionManager.shared

        // Get current pending transactions (polling automatically updates them)
        let hasPending = pendingTxManager.hasPendingTransactions(for: tx.coin.address, chain: tx.coin.chain)

        // Update SendCryptoViewModel properties and start/stop countdown timer
        if hasPending {
            sendCryptoViewModel.hasPendingTransaction = true
            sendCryptoViewModel.isCheckingPendingTransactions = false
            startCountdownTimer()

            // Start polling APENAS se for chain que suporta pending transactions
            if tx.coin.chain.supportsPendingTransactions {
                PendingTransactionManager.shared.startPollingForChain(tx.coin.chain)
            }
        } else {
            sendCryptoViewModel.hasPendingTransaction = false
            sendCryptoViewModel.pendingTransactionCountdown = 0
            sendCryptoViewModel.isCheckingPendingTransactions = false
            stopCountdownTimer()

            // SEMPRE para polling quando não há pendentes (qualquer chain)
            PendingTransactionManager.shared.stopPollingForChain(tx.coin.chain)
        }

    }

    private func startCountdownTimer() {
        stopCountdownTimer() // Stop any existing timer
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateCountdown()
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateCountdown() {
        guard tx.coin.chain.supportsPendingTransactions else {
            return
        }

        let pendingTxManager = PendingTransactionManager.shared

        if let oldestPending = pendingTxManager.getOldestPendingTransaction(for: tx.coin.address, chain: tx.coin.chain) {
            let elapsedSeconds = Int(Date().timeIntervalSince(oldestPending.timestamp))
            sendCryptoViewModel.pendingTransactionCountdown = elapsedSeconds
            // Keep transaction as pending - only confirmation should release it
            sendCryptoViewModel.hasPendingTransaction = true

        } else {
            // No more pending transactions - they were confirmed and removed
            sendCryptoViewModel.hasPendingTransaction = false
            sendCryptoViewModel.pendingTransactionCountdown = 0
            stopCountdownTimer()

        }
    }
}

#Preview {
    SendDetailsScreen(
        coin: Coin.example,
        tx: SendTransaction(),
        sendDetailsViewModel: SendDetailsViewModel(),
        vault: Vault.example
    )
    .environmentObject(CoinSelectionViewModel())
    .environmentObject(DeeplinkViewModel())
}
