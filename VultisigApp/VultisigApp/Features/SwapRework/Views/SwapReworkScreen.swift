//
//  SwapReworkScreen.swift
//  VultisigApp
//
//  Swap R3, behind `SwapReworkConfig`. The amount is typed on the in-app
//  keypad ("." decimals in every locale), the quote lives in one route card
//  that opens the ranked route sheet, fees expand into an honest breakdown
//  with the VULT tier discount, and whatever blocks the swap is shown on the
//  element that caused it with one fix. Review is the existing keysign review
//  sheet (Paired / Fast Sign), presented exactly as the old form presents it.
//

import SwiftUI

struct SwapReworkScreen: View {
    let fromCoin: Coin?
    let toCoin: Coin?
    let vault: Vault

    @State private var viewModel = SwapReworkViewModel()
    @State private var isEditingAmount = true
    @State private var selectedSwapMode: SwapFormMode = .market
    @State private var catalogSide: SwapReworkPickerSide?
    @State private var catalogChain: Chain?
    @State private var showApprovalSteps = false
    @State private var showAdvancedLockedSheet = false
    @State private var showAddGas = false
    @State private var showReceiveGas = false
    @State private var addressToCopy: Coin?
    /// Set when Buy pushes the Banxa flow, so coming back re-reads balances.
    @State private var isAwayForFunding = false
    @Environment(\.scenePhase) private var scenePhase

    private let tierService = VultTierService()

    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter
    @Environment(\.router) private var router

    private var details: SwapDetailsViewModel { viewModel.details }
    private var state: SwapReworkFormState { viewModel.state }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 12) {
                if !isProgressDemo {
                    swapModeTabs
                        .fixedSize()
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                switch selectedSwapMode {
                case .market:
                    marketContent
                case .limit:
                    LimitSwapEntryView(initialFromCoin: details.fromCoin, initialToCoin: details.toCoin, vault: vault)
                        .environmentObject(coinSelectionViewModel)
                }
            }
        }
        .screenTitle("swap".localized)
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                HStack(spacing: 8) {
                    historyButton
                    advancedSettingsButton
                }
            }
        }
        .crossPlatformSheet(isPresented: advancedSheetBinding) {
            @Bindable var vm = details
            AdvancedSwapSheet(
                isPresented: $vm.showAdvancedSettingsSheet,
                coin: details.toCoin,
                isGasLimitSupported: details.isGasLimitSupported,
                settings: $vm.advancedSettings,
                detailsViewModel: details,
                vault: vault
            )
        }
        .crossPlatformSheet(isPresented: $showAdvancedLockedSheet) {
            LockedFeatureSheet(
                feature: .swapAdvancedSettings,
                vault: vault,
                isPresented: $showAdvancedLockedSheet
            ) {
                showAdvancedLockedSheet = false
                router.navigate(to: VaultRoute.swap(
                    fromCoin: vault.nativeCoin(for: .ethereum),
                    toCoin: tierService.getVultToken(for: vault),
                    vault: vault
                ))
            }
        }
        .onChange(of: details.showAdvancedSettingsSheet) { wasPresented, isPresented in
            // Same contract as the old form: re-quote on close only when a
            // quote-affecting setting changed (the details view model decides).
            if wasPresented && !isPresented {
                details.advancedSettingsSheetDidClose(vault: vault)
            }
        }
        .crossPlatformSheet(item: $viewModel.pickerSide) { side in
            SwapReworkTokenPicker(
                title: (side == .pay ? "swapReworkPayWith" : "swapReworkReceiveTitle").localized,
                rows: viewModel.pickerRows(side: side),
                recentIDs: viewModel.recentIDs,
                selectedID: side == .pay ? state.pay.coinID : state.receive.coinID,
                onSelect: { viewModel.selectToken($0, side: side) },
                onBrowseCatalog: { chainName in openCatalog(side: side, chainName: chainName) },
                onClose: { viewModel.pickerSide = nil }
            )
            .sheetStyle(padding: 0)
        }
        .crossPlatformSheet(item: $catalogSide) { side in
            catalogPicker(side: side)
        }
        .crossPlatformSheet(isPresented: $viewModel.showRouteSheet) {
            SwapReworkRouteSheet(
                routes: state.routes,
                selectedID: state.selectedRouteID,
                receiveTicker: state.receive.ticker,
                receiveIsBitcoin: state.receive.chainName == Chain.bitcoin.name && state.receive.isNative,
                timer: state.timer,
                gasNote: state.routeGasNote,
                onSelect: { viewModel.selectRoute(id: $0, vault: vault) }
            )
            // Tall enough for three routes and the footer; drag up for more.
            .sheetStyle(padding: 0, detents: [.fraction(0.7), .large])
        }
        .crossPlatformSheet(isPresented: $showAddGas) {
            SwapReworkAddGasSheet(
                ticker: state.feeTicker,
                chainName: viewModel.isDemo ? "Ethereum" : details.feeCoin.chain.name,
                amountText: state.gasToAddText ?? demoGasToAdd,
                addressText: viewModel.isDemo ? "0x4a7e…91c2" : SwapTokenTrust.shortContract(details.feeCoin.address),
                onReceive: {
                    showAddGas = false
                    guard !viewModel.isDemo else { return }
                    showReceiveGas = true
                },
                onBuy: {
                    showAddGas = false
                    guard !viewModel.isDemo else { return }
                    let feeCoin = details.feeCoin
                    isAwayForFunding = true
                    router.navigate(to: HomeRoute.vaultAction(
                        action: .buy(address: feeCoin.address, blockChainCode: feeCoin.chain.banxaBlockchainCode, coinType: feeCoin.ticker),
                        vault: vault
                    ))
                }
            )
            .sheetStyle(padding: 0, detents: [.medium])
        }
        .crossPlatformSheet(isPresented: $showReceiveGas, onDismiss: refreshFunding) {
            ReceiveQRCodeBottomSheet(
                coin: details.feeCoin,
                isNativeCoin: true,
                onClose: { showReceiveGas = false },
                onShare: { showReceiveGas = false },
                onCopy: { coin in
                    showReceiveGas = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { addressToCopy = coin }
                }
            )
        }
        .withAddressCopy(coin: $addressToCopy)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshFunding() }
        }
        .onAppear {
            guard isAwayForFunding else { return }
            isAwayForFunding = false
            refreshFunding()
        }
        .crossPlatformSheet(isPresented: $showApprovalSteps) {
            if let approval = state.approval {
                SwapReworkApprovalStepsView(approval: approval, receiveTicker: state.receive.ticker)
                    .sheetStyle(padding: 0, detents: [.medium])
            }
        }
        .onLoad { load() }
        .swapRefreshTick {
            viewModel.tick(vault: vault, isReviewPresented: reviewPresenter.isPresenting)
        }
        .onChange(of: details.fromCoin) { _, coin in
            guard !viewModel.isDemo else { return }
            details.updateFromCoin(coin: coin, vault: vault)
            viewModel.coinsChanged()
        }
        .onChange(of: details.toCoin) { _, coin in
            guard !viewModel.isDemo else { return }
            details.updateToCoin(coin: coin, vault: vault)
            viewModel.coinsChanged()
        }
        .onChange(of: details.quote) { _, _ in
            // A route pick swaps the quote (and so the spender) without a
            // quote fetch; re-resolve the approval for whatever is on screen.
            guard !viewModel.isDemo else { return }
            viewModel.refreshApproval()
        }
        .onChange(of: details.isLoadingFees) { wasLoading, isLoading in
            if wasLoading && !isLoading { viewModel.feesSettled(vault: vault) }
        }
        .onChange(of: details.isLoadingQuotes) { wasLoading, isLoading in
            if wasLoading && !isLoading { viewModel.quoteFetchSettled(vault: vault) }
        }
        .withBanner(text: routeNotice, style: .error)
    }

    // MARK: - Market

    @ViewBuilder
    private var marketContent: some View {
        #if DEBUG
        if let scenario = SwapReworkConfig.demoScenario, [.tracker, .success, .received, .notifyOn, .notifyDenied].contains(scenario) {
            progressDemo(scenario)
        } else {
            form
        }
        #else
        form
        #endif
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    amountCards
                    quoteArea
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.never)

            VStack(spacing: 8) {
                ctaButton
                    // A one-line control: at accessibility sizes its label
                    // would widen the whole form past the screen.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                if showsKeypad {
                    PerpsKeypad { viewModel.press($0, vault: vault) }
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .animation(.easeInOut(duration: 0.2), value: showsKeypad)
        }
    }

    /// The keypad is up while typing, and always when there is no amount yet:
    /// an empty form has nothing else to do.
    private var showsKeypad: Bool {
        isEditingAmount || state.isEmpty
    }

    private var amountCards: some View {
        // The flip button sits on the seam, overlapping both cards.
        VStack(spacing: -14) {
            SwapReworkPayCard(
                state: state,
                isEditing: showsKeypad,
                onTapAmount: { isEditingAmount = true },
                onTapToken: { viewModel.pickerSide = .pay },
                onPercent: { percentage in
                    // The amount is set: put the quote in view, as R3 does.
                    isEditingAmount = false
                    viewModel.selectPercent(percentage, vault: vault)
                }
            )
            SwapReworkFlipButton {
                guard !viewModel.isDemo else { return }
                viewModel.flip(vault: vault)
                isEditingAmount = true
            }
            .zIndex(1)
            SwapReworkReceiveCard(state: state, onTapToken: { viewModel.pickerSide = .receive })
        }
    }

    @ViewBuilder
    private var quoteArea: some View {
        if let issue = state.issue {
            SwapReworkIssueCard(
                issue: issue,
                pair: (state.pay.ticker, state.receive.ticker),
                gasDetail: gasDetail,
                minimumText: state.minimumText,
                gasActionTitle: String(format: "swapReworkAddGasChip".localized, state.feeTicker),
                onGasAction: { showAddGas = true }
            )
        }
        if let warning = state.feeWarning {
            SwapReworkFeeWarningCard(warning: warning)
        }
        if let loss = state.valueLossText {
            SwapReworkValueLossCard(lossText: loss)
        }
        if let route = state.route, state.issue != .noRoute {
            SwapReworkRouteCard(
                route: route,
                timer: state.timer,
                fees: viewModel.showFeeDetails || isEditingAmount ? nil : state.fees,
                onTap: {
                    isEditingAmount = false
                    if route.isSelectable { viewModel.showRouteSheet = true }
                },
                onTapFees: {
                    isEditingAmount = false
                    viewModel.showFeeDetails = true
                }
            )
        } else if state.isQuoteLoading {
            loadingRouteCard
        }
        if let approval = state.approval, state.issue == nil || state.issue == .notEnoughGas {
            Button { showApprovalSteps = true } label: {
                SwapReworkApprovalCard(approval: approval)
            }
            .buttonStyle(.plain)
        }
        if let fees = state.fees, viewModel.showFeeDetails {
            SwapReworkFeeCard(fees: fees, isExpanded: viewModel.showFeeDetails) {
                isEditingAmount = false
                viewModel.showFeeDetails.toggle()
            }
        }
    }

    private var loadingRouteCard: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.colors.bgSurface2).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                SwapReworkSkeleton(width: 120, height: 12)
                SwapReworkSkeleton(width: 180, height: 10)
            }
            Spacer()
            ProgressView().tint(Theme.colors.primaryAccent4)
        }
        .padding(16)
        .swapReworkCard(highlighted: false)
    }

    private func refreshFunding() {
        Task { await viewModel.refreshFunding(vault: vault) }
    }

    private var demoGasToAdd: String? {
        #if DEBUG
        if viewModel.isDemo { return "0.00088 ETH ($1.72)" }
        #endif
        return nil
    }

    private var gasDetail: String? {
        #if DEBUG
        if let scenario = SwapReworkConfig.demoScenario { return SwapReworkDemo.gasShortfallText(for: scenario) }
        #endif
        return viewModel.gasShortfallText
    }

    // MARK: - CTA

    private var ctaButton: some View {
        PrimaryButton(title: ctaTitle, isLoading: state.cta == .loading) {
            handleCTA()
        }
        .disabled(!state.isCTAEnabled)
        .opacity(state.isCTAEnabled ? 1 : 0.5)
        .accessibilityIdentifier("swapReworkCTA")
    }

    private var ctaTitle: String {
        switch state.cta {
        case .enterAmount: return state.issue == nil ? "swapReworkEnterAmount".localized : "swapReworkCannotSwap".localized
        case .loading: return "swapReworkGettingPrice".localized
        case .review: return "swapReworkReview".localized
        case .reviewWith(let provider): return String(format: "swapReworkReviewWith".localized, provider)
        case .confirmNewAmount: return "swapReworkConfirmNewAmount".localized
        case .getNewQuote: return "swapReworkGetNewQuote".localized
        case .chooseAnotherCoin: return "swapReworkChooseAnother".localized
        case .insufficient(let ticker): return String(format: "swapInsufficientTokenBalance".localized, ticker)
        case .fixGas(let ticker): return String(format: "swapReworkNotEnoughGasCTA".localized, ticker)
        case .useMinimum(let amount): return String(format: "swapReworkUseMinimum".localized, amount)
        }
    }

    private func handleCTA() {
        switch state.cta {
        case .review, .reviewWith:
            presentReview()
        case .confirmNewAmount:
            viewModel.confirmNewAmount()
        case .getNewQuote:
            viewModel.requestNewQuote(vault: vault)
        case .chooseAnotherCoin:
            viewModel.pickerSide = .receive
        case .useMinimum:
            viewModel.useMinimum(vault: vault)
        case .enterAmount, .loading, .insufficient, .fixGas:
            break
        }
    }

    /// The existing hand-off: read the approval once, then the shared review
    /// sheet. Nothing here builds or signs a transaction itself.
    private func presentReview() {
        guard !viewModel.isDemo else { return }
        isEditingAmount = false
        viewModel.willPresentReview()
        let quoteAtTap = details.quote
        Task {
            guard let transaction = await details.prepareTransaction(vault: vault) else { return }
            guard viewModel.canStillPresent(quoteAtTap: quoteAtTap) else {
                viewModel.requestNewQuote(vault: vault)
                return
            }
            reviewPresenter.present(.swap(
                transaction: transaction,
                retrySignal: SwapRetrySignal(),
                vaultPubKeyECDSA: vault.pubKeyECDSA
            ))
        }
    }

    // MARK: - Pickers

    private func openCatalog(side: SwapReworkPickerSide, chainName: String?) {
        let current = side == .pay ? details.fromCoin.chain : details.toCoin.chain
        catalogChain = chainName.flatMap { name in Chain.allCases.first { $0.name == name } } ?? current
        viewModel.pickerSide = nil
        guard !viewModel.isDemo else { return }
        catalogSide = side
    }

    @ViewBuilder
    private func catalogPicker(side: SwapReworkPickerSide) -> some View {
        @Bindable var vm = details
        SwapCoinPickerView(
            vault: vault,
            showSheet: Binding(get: { catalogSide != nil }, set: { if !$0 { catalogSide = nil } }),
            selectedCoin: side == .pay ? $vm.fromCoin : $vm.toCoin,
            selectedChain: catalogChain,
            isDestination: side == .receive
        )
        .environmentObject(coinSelectionViewModel)
    }

    // MARK: - Advanced settings

    private var advancedSheetBinding: Binding<Bool> {
        Binding(
            get: { details.showAdvancedSettingsSheet },
            set: { details.showAdvancedSettingsSheet = $0 }
        )
    }

    /// Past swaps, as in R3's header: the vault's history.
    private var historyButton: some View {
        ToolbarButton(image: .clockRotateClockwise, type: .outline) {
            router.navigate(to: TransactionHistoryRoute.list(
                pubKeyECDSA: vault.pubKeyECDSA,
                vaultName: vault.name,
                chainFilter: nil
            ))
        }
        .accessibilityLabel("swapReworkHistory".localized)
    }

    private var advancedSettingsButton: some View {
        ToolbarButton(image: .slidersVertical, type: .outline) {
            handleAdvancedSettingsTap()
        }
        .accessibilityLabel("advancedSettings".localized)
    }

    /// The old form's gate, unchanged: Silver and up open the existing
    /// advanced sheet (slippage, gas limit, recipient, route); below that the
    /// locked-feature sheet explains the tier.
    private func handleAdvancedSettingsTap() {
        isEditingAmount = false
        if viewModel.isDemo {
            // Debug fixtures have no vault tier to check; open the sheet as-is.
            details.snapshotAdvancedSettings()
            details.showAdvancedSettingsSheet = true
            return
        }
        Task {
            await TierGatedTap.handle(
                required: .silver,
                show: lockedSheetBinding,
                for: vault,
                isUnlocked: { tier, vault in
                    guard let cached = await tierService.fetchDiscountTier(for: vault, cached: true) else {
                        return false
                    }
                    return cached >= tier
                },
                onUnlocked: {
                    details.snapshotAdvancedSettings()
                    details.showAdvancedSettingsSheet = true
                }
            )
        }
    }

    private var lockedSheetBinding: Binding<VultDiscountTier?> {
        Binding(
            get: { showAdvancedLockedSheet ? .silver : nil },
            set: { showAdvancedLockedSheet = $0 != nil }
        )
    }

    // MARK: - Tabs

    private var swapModeTabs: some View {
        SegmentedControl(
            selection: $selectedSwapMode,
            items: [
                SegmentedControlItem(value: SwapFormMode.market, title: "swap.tab.market".localized),
                SegmentedControlItem(
                    value: SwapFormMode.limit,
                    title: "swap.tab.limit".localized,
                    isEnabled: !viewModel.isDemo && vault.chains.contains(where: { isThorchainRoutable(chain: $0) })
                )
            ]
        )
    }

    private var routeNotice: Binding<String?> {
        Binding(
            get: { selectedSwapMode == .market ? details.routeSelectionNotice : nil },
            set: { details.routeSelectionNotice = $0 }
        )
    }

    // MARK: - Lifecycle

    private func load() {
        #if DEBUG
        if let scenario = SwapReworkConfig.demoScenario {
            applyDemo(scenario)
            return
        }
        #endif
        details.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault)
        details.warmDiscountTier(vault: vault)
        details.fromChain = details.fromCoin.chain
        details.toChain = details.toCoin.chain
    }

    private var isProgressDemo: Bool {
        #if DEBUG
        guard let scenario = SwapReworkConfig.demoScenario else { return false }
        return [.tracker, .success, .received, .notifyOn, .notifyDenied].contains(scenario)
        #else
        false
        #endif
    }

    #if DEBUG
    private func applyDemo(_ scenario: SwapReworkDemoScenario) {
        isEditingAmount = [.empty, .quote, .maxGas].contains(scenario)
        switch scenario {
        case .fees, .approval, .noGas, .approvalFees:
            viewModel.showFeeDetails = scenario == .fees || scenario == .approvalFees
        case .routes:
            viewModel.showRouteSheet = true
        case .picker, .unverified, .pickerSmall:
            viewModel.pickerSide = .pay
        case .addGas:
            showAddGas = true
        case .steps:
            showApprovalSteps = true
        default:
            break
        }
    }

    @ViewBuilder
    private func progressDemo(_ scenario: SwapReworkDemoScenario) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                Group {
                    switch scenario {
                    case .tracker, .notifyOn, .notifyDenied:
                        VStack(spacing: 16) {
                            SwapReworkTrackerView(state: SwapReworkDemo.tracker)
                            SwapReworkNotifyCard(
                                state: scenario == .notifyOn ? .on : (scenario == .notifyDenied ? .permissionDenied : .off),
                                ticker: "BTC",
                                onTurnOn: {}, onTurnOff: {}, onOpenSettings: {}
                            )
                        }
                    case .received: SwapReworkSuccessView(state: SwapReworkDemo.received)
                    default: SwapReworkSuccessView(state: SwapReworkDemo.success)
                    }
                }
                .padding(16)
            }
            HStack(spacing: 10) {
                if [.success, .received].contains(scenario) {
                    PrimaryButton(title: "swapReworkSwapAgain".localized, type: .secondary) {}
                }
                PrimaryButton(title: ([.success, .received].contains(scenario) ? "done" : "swapReworkBackToVault").localized) {}
            }
            .padding(16)
        }
    }
    #endif
}
