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
    case destinationTag
}

struct SendDetailsScreen: View {
    @State var coin: Coin?
    @State var viewModel: SendDetailsViewModel
    let vault: Vault
    @State var settingsPresented: Bool = false

    @FocusState var focusedField: Field?
    @State private var displayedTab: SendDetailsFocusedTab?
    @State private var isNavigatingForward = true
    #if os(iOS)
    @State private var scrollViewMaxY: CGFloat = 0
    @State private var floatingButtonMinY: CGFloat = 0
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter
    @Environment(\.router) private var router

    init(coin: Coin?, viewModel: SendDetailsViewModel, vault: Vault) {
        self._coin = State(initialValue: coin)
        self._viewModel = State(initialValue: viewModel)
        self.vault = vault
    }

    var body: some View {
        container
            .disabled(viewModel.showLoader)
            .withLoading(isLoading: $viewModel.isValidatingForm)
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
                // Clear any previously-typed memo when switching into a coin
                // whose signer cannot carry it so it doesn't ride invisibly.
                if !newValue.supportsMemo {
                    viewModel.memo = ""
                }
                // Same treatment for the XRP-only destination tag.
                if !newValue.chain.supportsDestinationTag {
                    viewModel.rippleTag.clearForUnsupportedChain()
                }
                // The amount now describes another asset, so its max-send intent and pending commit lapse.
                viewModel.convertToFiat(newValue: viewModel.amount)
                // Re-evaluate (or clear, when no validator applies) the inline
                // amount warning when the selected coin changes.
                viewModel.debouncedValidateAmount()
                if oldValue.chain != newValue.chain {
                    // Re-check so the header cannot offer Amount with an address the new chain rejects.
                    Task { await viewModel.recheckRecipient(clearingSetupFirst: true) }
                }
            }
            .onChange(of: viewModel.toAddress) { _, _ in
                viewModel.handleToAddressChange()
            }
            .onChange(of: viewModel.amount) { _, _ in
                viewModel.debouncedValidateAmount()
            }
            .onChange(of: viewModel.isAddressResolved) { _, resolved in
                guard let resolved else { return }
                viewModel.handleAddressResolution(resolved)
            }
            .onDisappear {
                if !router.isShowingSigningRoute {
                    viewModel.stopMediator()
                }
                viewModel.tearDownPendingTransactionState()
            }
            .crossPlatformSheet(isPresented: $settingsPresented) {
                SendGasSettingsView(
                    isPresented: $settingsPresented,
                    viewModel: SendGasSettingsViewModel(
                        coin: viewModel.coin,
                        vault: vault,
                        gasLimit: viewModel.gasLimit,
                        customGasLimit: viewModel.customGasLimit,
                        customByteFee: viewModel.customByteFee,
                        selectedMode: viewModel.feeMode,
                        fromAddress: viewModel.fromAddress,
                        toAddress: viewModel.toAddress,
                        amount: viewModel.amountInRaw,
                        memo: viewModel.memo.isEmpty ? nil : viewModel.memo
                    ),
                    output: self
                )
            }
    }

    var content: some View {
        view
            .onChange(of: viewModel.coin) { _, _ in
                setData()
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
        if viewModel.selectedTab == .asset, !viewModel.isCoinShownOnAssetStep {
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
        // `@Bindable` on the nested sub-VM: a binding can't chain through the
        // parent's `let rippleTag` (read-only key path), so bind locally.
        @Bindable var rippleTag = viewModel.rippleTag
        return tabsContent
            // Fail-open half of the XRP RequireDest gate: the lookup
            // couldn't confirm whether the destination needs a tag, so the
            // user must explicitly accept the risk before the send proceeds.
            .alert(
                NSLocalizedString("destinationTagUnverifiedTitle", comment: ""),
                isPresented: $rippleTag.showDestinationTagUnverifiedAlert
            ) {
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("continueAnyway", comment: "")) {
                    viewModel.acknowledgeUnverifiedDestinationTag()
                    Task { await validateForm() }
                }
            } message: {
                Text(NSLocalizedString("destinationTagUnverifiedWarning", comment: ""))
            }
    }

    /// Fixed gap between the title and the scroll viewport; it does not scroll.
    private static let titleToScrollGap: CGFloat = 12
    /// Height of the viewport's top-edge fade; the panes start this far down so nothing is dimmed at rest.
    private static let scrollEdgeFadeHeight: CGFloat = 12

    var tabsContent: some View {
        VStack(spacing: 0) {
            SendDetailsStepHeader(viewModel: viewModel, displayedTab: displayedTab, horizontalInset: Self.horizontalInset)

            ScrollView {
                panes
                    .padding(.top, Self.scrollEdgeFadeHeight)
                    .padding(.bottom, panesBottomPadding)
            }
            // Only the asset search drops the keyboard on scroll; the amount field keeps it.
            .scrollDismissesKeyboard(displayedTab == .asset ? .immediately : .automatic)
            .refreshable {
                await onRefresh()
            }
            .mask { scrollEdgeMask }
            .padding(.top, Self.titleToScrollGap)
            #if os(iOS)
            .ignoresSafeArea(.container, edges: .bottom)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { scrollViewMaxY = $0 }
            #endif
        }
        .onChange(of: viewModel.selectedTab) { oldValue, newValue in
            onSelectedTabChange(oldTab: oldValue, newTab: newValue)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.selectedTab) { oldTab, newTab in
            guard let oldTab, let newTab else { return false }
            return newTab > oldTab
        }
    }

    /// Content scrolled under the title dissolves instead of being cut.
    private var scrollEdgeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.scrollEdgeFadeHeight)
            Rectangle()
        }
    }

    /// All steps stay mounted so each `isShown` handler runs on enter and leave; only the shown one has content.
    var panes: some View {
        ZStack(alignment: .top) {
            SendDetailsAssetTab(
                isShown: displayedTab == .asset,
                transition: paneTransition,
                horizontalInset: Self.horizontalInset,
                viewModel: viewModel
            )

            SendDetailsAddressTab(
                isShown: displayedTab == .address,
                transition: paneTransition,
                viewModel: viewModel,
                focusedField: $focusedField
            )
            .padding(.horizontal, Self.horizontalInset)

            SendDetailsAmountTab(
                isShown: displayedTab == .amount,
                transition: paneTransition,
                viewModel: viewModel,
                validateForm: validateForm,
                focusedField: $focusedField,
                settingsPresented: $settingsPresented
            )
            .padding(.horizontal, Self.horizontalInset)
        }
    }

    var paneTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: isNavigatingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isNavigatingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    func onSelectedTabChange(oldTab: SendDetailsFocusedTab?, newTab: SendDetailsFocusedTab?) {
        if newTab != .address && newTab != .amount {
            focusedField = nil
        }
        guard let oldTab, let newTab else {
            displayedTab = newTab
            return
        }
        isNavigatingForward = newTab > oldTab
        // A leaving pane slides with the transition it last rendered, so render the new direction first.
        Task {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) {
                displayedTab = viewModel.selectedTab
            }
        }
    }

    func validateForm() async {
        guard !viewModel.isValidatingForm, !reviewPresenter.isPresenting else { return }
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
                    guard !reviewPresenter.isPresenting else { return }
                    do {
                        let immutableTx = try viewModel.makeTransaction()
                        // Release focus before the review opens, so the
                        // keyboard is not left up under the sheet and the field
                        // does not come back focused when it closes.
                        focusedField = nil
                        // Clear the previous session before review can start a
                        // new one. A navigation push may start pairing before
                        // this screen disappears, so disappearance cannot own it.
                        viewModel.stopMediator()
                        reviewPresenter.present(.send(
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

    func setData() {
        Task {
            await getBalance()
        }
    }

    private func onRefresh() async {
        async let pendingCheck: Void = viewModel.forceCheckPendingTransactions()
        // Awaited here rather than in an `async let`: a child task would read
        // the coin off the main actor before `updateBalance` hops back to it.
        await BalanceService.shared.updateBalance(for: viewModel.coin)
        await pendingCheck
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
            let seeded = (amount: viewModel.amount, amountInFiat: viewModel.amountInFiat, memo: viewModel.memo)
            viewModel.reset(to: coin)
            viewModel.amount = seeded.amount
            viewModel.amountInFiat = seeded.amountInFiat
            viewModel.memo = seeded.memo
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
                guard let resolved = await viewModel.validateToAddressIfUnchanged() else { return }
                viewModel.addressSetupDone = resolved
                if resolved {
                    viewModel.onSelect(tab: .amount)
                }
            }
        }
    }

}

#if os(iOS)
import SwiftUI

extension SendDetailsScreen {
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

    static let horizontalInset: CGFloat = 24
    private static let floatingButtonGap: CGFloat = 16

    var container: some View {
        Screen {
            content
        }
        .screenTitle("send".localized)
        .screenEdgeInsets(ScreenEdgeInsets(leading: 0, bottom: 0, trailing: 0))
    }

    /// The panes scroll under the floating Continue button to the screen edge.
    var view: some View {
        ZStack(alignment: .bottom) {
            tabs
            buttonContainer
        }
    }

    /// Lets the last row and the fee row scroll clear of the floating button, keyboard up or not.
    var panesBottomPadding: CGFloat {
        max(scrollViewMaxY - floatingButtonMinY, 0) + Self.floatingButtonGap
    }

    var buttonContainer: some View {
        button
            .padding(.vertical, 8)
            .padding(.horizontal, Self.horizontalInset)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { floatingButtonMinY = $0 }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension SendDetailsScreen {
    static let horizontalInset: CGFloat = 40
    private static let macButtonExtraInset: CGFloat = 8
    private static let bottomPadding: CGFloat = 65

    var panesBottomPadding: CGFloat { Self.bottomPadding }

    var container: some View {
        Screen {
            content
        }
        .screenTitle("send".localized)
        .screenEdgeInsets(ScreenEdgeInsets(leading: 0, trailing: 0))
    }

    var view: some View {
        VStack {
            tabs
            button
                .padding(.horizontal, Self.horizontalInset + Self.macButtonExtraInset)
        }
    }
}
#endif
