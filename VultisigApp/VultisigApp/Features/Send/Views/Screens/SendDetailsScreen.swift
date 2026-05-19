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
    @State var viewModel: SendDetailsViewModel
    let vault: Vault
    @State var settingsPresented: Bool = false

    @StateObject var keyboardObserver = KeyboardObserver()

    @FocusState var focusedField: Field?
    @State var scrollProxy: ScrollViewProxy?

    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @Environment(\.router) var router

    init(coin: Coin?, viewModel: SendDetailsViewModel, vault: Vault) {
        self._coin = State(initialValue: coin)
        self._viewModel = State(initialValue: viewModel)
        self.vault = vault
    }

    var body: some View {
        container
            .disabled(viewModel.showLoader)
            .overlay(viewModel.showLoader ? Loader() : nil)
            .onAppear {
                viewModel.initializePendingTransactionState(for: viewModel.coin.chain)
                viewModel.refreshPendingTransactionState()
            }
            .onLoad {
                viewModel.onLoad()
                Task {
                    await setMainData()
                    viewModel.refreshPendingTransactionState()
                }
                setData()
            }
            .onChange(of: viewModel.coin) { oldValue, newValue in
                viewModel.initializePendingTransactionState(for: newValue.chain)
                PendingTransactionManager.shared.stopPollingForChain(oldValue.chain)
                viewModel.refreshPendingTransactionState()
                // Per-chain capability lives on `Chain.supportsMemo`. Clear
                // any previously-typed memo when switching into a chain that
                // doesn't support memos so it doesn't ride along invisibly.
                // (See #4326 / #4377 for the Cardano case.)
                if !newValue.chain.supportsMemo {
                    viewModel.memo = ""
                }
            }
            .onChange(of: viewModel.toAddress) { _, _ in
                viewModel.cancelAddressResolution()

                guard !viewModel.toAddress.isEmpty else {
                    viewModel.addressSetupDone = false
                    return
                }

                if viewModel.isValidAddressFormat() {
                    viewModel.addressSetupDone = true
                    viewModel.onSelect(tab: .amount)
                } else {
                    viewModel.debouncedResolveAddress()
                }
            }
            .onChange(of: viewModel.isAddressResolved) { _, resolved in
                guard let resolved else { return }
                viewModel.addressSetupDone = resolved
                if resolved {
                    viewModel.onSelect(tab: .amount)
                } else if viewModel.selectedTab == .amount {
                    viewModel.onSelect(tab: .address)
                }
            }
            .onDisappear {
                viewModel.stopMediator()
                viewModel.tearDownPendingTransactionState()
            }
            .crossPlatformSheet(isPresented: $settingsPresented) {
                SendGasSettingsView(
                    isPresented: $settingsPresented,
                    viewModel: SendGasSettingsViewModel(
                        coin: viewModel.coin,
                        vault: vault,
                        gasLimit: viewModel.gasLimit,
                        customByteFee: viewModel.customByteFee,
                        selectedMode: viewModel.feeMode
                    ),
                    output: self
                )
            }
            .crossPlatformSheet(isPresented: $viewModel.showChainPickerSheet) {
                SwapChainPickerView(
                    vault: vault,
                    showSheet: $viewModel.showChainPickerSheet,
                    selectedChain: $viewModel.selectedChain
                )
                .environmentObject(coinSelectionViewModel)
            }
            .crossPlatformSheet(isPresented: $viewModel.showCoinPickerSheet) {
                SwapCoinPickerView(
                    vault: vault,
                    showSheet: $viewModel.showCoinPickerSheet,
                    selectedCoin: $viewModel.coin,
                    selectedChain: viewModel.selectedChain
                )
                .environmentObject(coinSelectionViewModel)
            }
    }

    var content: some View {
        view
            .onChange(of: viewModel.coin) { _, _ in
                setData()
            }
            .onChange(of: focusedField) { _, focusedField in
                onChange(focusedField: focusedField)
            }
            .alert(isPresented: $viewModel.showAlert) {
                alert
            }
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(viewModel.errorTitle, comment: "")),
            message: Text(NSLocalizedString(viewModel.errorMessage ?? .empty, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }

    var button: some View {
        PrimaryButton(
            title: getButtonTitle(),
            isLoading: viewModel.isLoading && !viewModel.hasPendingTransaction
        ) {
            Task {
                await validateForm()
            }
        }
        .disabled(getButtonDisabled())
    }

    private func getButtonDisabled() -> Bool {
        if viewModel.continueButtonDisabled {
            return true
        }
        if viewModel.coin.chain.supportsPendingTransactions {
            if viewModel.isCheckingPendingTransactions {
                return true
            }
            if viewModel.hasPendingTransaction {
                return true
            }
        }
        return false
    }

    private func getButtonTitle() -> String {
        if viewModel.coin.chain.supportsPendingTransactions {
            if viewModel.isCheckingPendingTransactions {
                return "Checking pending transactions..."
            } else if viewModel.hasPendingTransaction {
                let elapsed = viewModel.pendingTransactionCountdown
                let minutes = elapsed / 60
                let seconds = elapsed % 60
                if minutes > 0 {
                    return "Pending transaction (\(minutes)m \(seconds)s)"
                } else {
                    return "Pending transaction (\(seconds)s)"
                }
            }
        }
        if viewModel.isLoading {
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
                        isExpanded: viewModel.selectedTab == .asset,
                        viewModel: viewModel
                    )
                    .id(SendDetailsFocusedTab.asset.rawValue)

                    SendDetailsAddressTab(
                        isExpanded: viewModel.selectedTab == .address,
                        viewModel: viewModel,
                        focusedField: $focusedField
                    )
                    .id(SendDetailsFocusedTab.address.rawValue)

                    SendDetailsAmountTab(
                        isExpanded: viewModel.selectedTab == .amount,
                        viewModel: viewModel,
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
            .onChange(of: viewModel.selectedTab) { oldValue, newValue in
                handleScroll(newValue: newValue, oldValue: oldValue)
                onSelectedTabChange(newTab: newValue)
            }
        }
    }

    func onChange(focusedField: Field?) {
        if focusedField == .toAddress {
            handleScroll(newValue: .address, oldValue: .asset, delay: 0.2)
        }
    }

    func onSelectedTabChange(newTab: SendDetailsFocusedTab?) {
        if newTab != .address && newTab != .amount {
            focusedField = nil
        }
    }

    func handleScroll(newValue: SendDetailsFocusedTab?, oldValue: SendDetailsFocusedTab?, delay: Double = 0.7) {
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

    func validateForm() async {
        switch viewModel.selectedTab {
        case .none:
            viewModel.onSelect(tab: .asset)
            return
        case .asset:
            viewModel.onSelect(tab: .address)
            return
        case .address:
            viewModel.onSelect(tab: .amount)
            return
        case .amount:
            viewModel.isValidatingForm = true
            viewModel.validateAmount(viewModel.amount)

            if await viewModel.validateForm() {
                await MainActor.run {
                    do {
                        let immutableTx = try viewModel.makeTransaction()
                        router.navigate(to: SendRoute.verify(
                            tx: immutableTx,
                            retrySignal: SendRetrySignal(),
                            vault: vault
                        ))
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                        viewModel.showAlert = true
                    }
                }
            }
        }

        await MainActor.run {
            viewModel.isValidatingForm = false
        }
    }

    func getBalance() async {
        await BalanceService.shared.updateBalance(for: viewModel.coin)
    }

    private func onRefresh() async {
        async let bal: Void = BalanceService.shared.updateBalance(for: viewModel.coin)
        async let pendingCheck: Void = viewModel.forceCheckPendingTransactions()
        _ = await (bal, pendingCheck)
    }
}

extension SendDetailsScreen: SendGasSettingsOutput {

    func didSetFeeSettings(chain: Chain, mode: FeeMode, gasLimit: BigInt?, byteFee: BigInt?) {
        switch chain.chainType {
        case .EVM:
            viewModel.customGasLimit = gasLimit
        case .UTXO, .Cardano:
            viewModel.customByteFee = byteFee
        default:
            return
        }
        viewModel.feeMode = mode
    }
}

extension SendDetailsScreen {
    private func setMainData() async {
        guard !viewModel.isLoading else { return }

        if let coin = coin {
            let savedToAddress = viewModel.toAddress.isEmpty ? nil : viewModel.toAddress
            viewModel.reset(to: coin)
            if let saved = savedToAddress {
                viewModel.toAddress = saved
            } else if viewModel.toAddress.isEmpty {
                viewModel.toAddress = deeplinkViewModel.address ?? ""
            }
            deeplinkViewModel.address = nil
            self.coin = nil
        } else {
            if viewModel.toAddress.isEmpty, let deeplinkAddress = deeplinkViewModel.address {
                viewModel.toAddress = deeplinkAddress
                deeplinkViewModel.address = nil
            }
        }

        if !viewModel.toAddress.isEmpty {
            if viewModel.isValidAddressFormat() {
                viewModel.addressSetupDone = true
                viewModel.onSelect(tab: .amount)
            } else {
                let resolved = await viewModel.validateToAddress()
                viewModel.addressSetupDone = resolved
                if resolved {
                    viewModel.onSelect(tab: .amount)
                }
            }
        }

        await viewModel.loadFastVault()
    }

}

#if os(iOS)
import SwiftUI

extension SendDetailsScreen {
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

    var container: some View {
        Screen {
            content
        }
        .screenTitle("send".localized)
    }

    var view: some View {
        ZStack(alignment: .bottom) {
            tabs
            buttonContainer
        }
    }

    var buttonContainer: some View {
        button
            .padding(.vertical, 8)
            .background(keyboardObserver.keyboardHeight == 0 ? .clear : Theme.colors.bgPrimary)
            .shadow(color: Theme.colors.bgPrimary, radius: keyboardObserver.keyboardHeight == 0 ? 0 : 15)
    }

    func setData() {
        keyboardObserver.keyboardHeight = 0
        Task {
            await getBalance()
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension SendDetailsScreen {
    var container: some View {
        Screen {
            content
        }
        .screenTitle("send".localized)
    }

    var view: some View {
        VStack {
            tabs
            button
                .padding(.horizontal, 8)
        }
    }

    func setData() {
        Task {
            await getBalance()
        }
    }
}
#endif
