//
//  SwapDetailsScreen.swift
//  VultisigApp
//

import SwiftUI

struct SwapDetailsScreen: View {
    let fromCoin: Coin?
    let toCoin: Coin?
    let vault: Vault

    @State private var detailsViewModel = SwapDetailsViewModel()
    @StateObject private var referredViewModel = ReferredViewModel()
    @StateObject private var keyboardObserver = KeyboardObserver()

    @State private var showErrorTooltip = false
    /// Local Market/Limit tab state. The Limit branch lives entirely
    /// inside `LimitSwapModeBody` (which owns its own form view model and
    /// drives the limit-swap pipeline via `SwapRoute.limitPair`) — flag-off
    /// renders the existing Market layout pixel-identical to pre-feature.
    @State private var selectedSwapMode: SwapFormMode = .market
    @State private var showAdvancedLockedSheet = false

    private let tierService = VultTierService()

    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.router) var router

    var body: some View {
        @Bindable var vm = detailsViewModel
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    swapModeTabs
                        .fixedSize()
                    Spacer(minLength: 8)
                    tabRowCountdown
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .showIf(settingsViewModel.limitSwapEnabled)

                switch selectedSwapMode {
                case .market:
                    VStack {
                        fields
                        continueButton
                    }
                case .limit:
                    LimitSwapEntryView(
                        initialFromCoin: limitInitialFromCoin,
                        initialToCoin: detailsViewModel.toCoin,
                        vault: vault
                    )
                    .environmentObject(coinSelectionViewModel)
                }
            }
        }
        .screenTitle("swap".localized)
        .crossPlatformSheet(isPresented: $vm.showAdvancedSettingsSheet) {
            AdvancedSwapSheet(
                isPresented: $vm.showAdvancedSettingsSheet,
                coin: detailsViewModel.toCoin,
                isGasLimitSupported: detailsViewModel.isGasLimitSupported,
                settings: $vm.advancedSettings,
                detailsViewModel: detailsViewModel
            )
        }
        .screenToolbar {
            // Glass button (shared toolbar background) first, then the custom
            // countdown pill (own background → shared hidden). The toolbar
            // renders the glass group ahead of the plain group, so this order
            // shows the advanced-settings button left of the countdown.
            CustomToolbarItem(placement: .trailing) {
                advancedSettingsButton
            }
            CustomToolbarItem(placement: .trailing, hideSharedBackground: true) {
                refreshCounter
            }
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
        .crossPlatformSheet(isPresented: $vm.showFromChainSelector) {
            SwapChainPickerView(
                filterType: .swap,
                vault: vault,
                showSheet: $vm.showFromChainSelector,
                selectedChain: $vm.fromChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $vm.showToChainSelector) {
            SwapChainPickerView(
                filterType: .swap,
                vault: vault,
                showSheet: $vm.showToChainSelector,
                selectedChain: $vm.toChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $vm.showFromCoinSelector) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $vm.showFromCoinSelector,
                selectedCoin: $vm.fromCoin,
                selectedChain: vm.fromChain,
                isDestination: false
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $vm.showToCoinSelector) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $vm.showToCoinSelector,
                selectedCoin: $vm.toCoin,
                selectedChain: vm.toChain,
                isDestination: true
            )
            .environmentObject(coinSelectionViewModel)
        }
        .onLoad {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            // `load(...)` seeds `detailsViewModel.fromCoin/toCoin`; no manual
            // re-assignment afterwards or `onChange` would re-fire the quote fetch.
            detailsViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault)
            detailsViewModel.warmDiscountTier(vault: vault)
            setData()
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .swapRefreshTick {
            detailsViewModel.updateTimer(vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
        .onChange(of: detailsViewModel.fromCoin) { _, _ in
            detailsViewModel.updateFromCoin(coin: detailsViewModel.fromCoin, vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
        .onChange(of: detailsViewModel.toCoin) { _, _ in
            detailsViewModel.updateToCoin(coin: detailsViewModel.toCoin, vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
        .onChange(of: detailsViewModel.fromChain) { _, _ in
            detailsViewModel.handleFromChainUpdate(vault: vault)
        }
        .onChange(of: detailsViewModel.toChain) { _, _ in
            detailsViewModel.handleToChainUpdate(vault: vault)
        }
        .onChange(of: detailsViewModel.showAdvancedSettingsSheet) { wasPresented, isPresented in
            // On dismiss (true → false), re-fetch quotes if a quote-affecting
            // setting changed (slippage / gas limit / external recipient). The
            // VM no-ops when nothing relevant changed, and route selection is not
            // part of the compared settings so it never triggers a re-fetch.
            if wasPresented && !isPresented {
                detailsViewModel.advancedSettingsSheetDidClose(
                    vault: vault,
                    referredCode: referredViewModel.savedReferredCode
                )
            }
        }
        .onChange(of: detailsViewModel.error?.localizedDescription) { _, newError in
            showErrorTooltip = newError != nil
        }
        .onChange(of: detailsViewModel.fromAmount) { _, _ in
            detailsViewModel.error = nil
        }
        .ignoresSafeArea(.keyboard)
    }

    var swapContent: some View {
        ZStack {
            amountFields

            ZStack {
                if let error = detailsViewModel.error {
                    SwapErrorTooltipView(
                        error: error,
                        showTooltip: $showErrorTooltip,
                        onDismissTooltip: {
                            showErrorTooltip = false
                            detailsViewModel.error = nil
                        }
                    )
                    .transition(.opacity)
                } else {
                    SwapAssetsButton(isLoading: detailsViewModel.isLoadingQuotes) {
                        handleSwapTap()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: detailsViewModel.error != nil)

            filler.offset(x: -28)
            filler.offset(x: 28)
        }
    }

    var amountFields: some View {
        VStack(spacing: 12) {
            swapFromField
            swapToField
        }
    }

    var swapFromField: some View {
        @Bindable var vm = detailsViewModel
        return SwapFromToField(
            title: "from",
            vault: vault,
            coin: detailsViewModel.fromCoin,
            fiatAmount: detailsViewModel.fromFiatAmount,
            amount: $vm.fromAmount,
            selectedChain: $vm.fromChain,
            showNetworkSelectSheet: $vm.showFromChainSelector,
            showCoinSelectSheet: $vm.showFromCoinSelector,
            detailsViewModel: detailsViewModel,
            handlePercentageSelection: handlePercentageSelection
        )
    }

    var swapToField: some View {
        @Bindable var vm = detailsViewModel
        return SwapFromToField(
            title: "to",
            vault: vault,
            coin: detailsViewModel.toCoin,
            fiatAmount: detailsViewModel.toFiatAmountDisplay,
            amount: .constant(detailsViewModel.toAmountDisplayString),
            selectedChain: $vm.toChain,
            showNetworkSelectSheet: $vm.showToChainSelector,
            showCoinSelectSheet: $vm.showToCoinSelector,
            detailsViewModel: detailsViewModel,
            handlePercentageSelection: nil
        )
    }

    var filler: some View {
        Rectangle()
            .frame(width: 12, height: 10)
            .foregroundStyle(Theme.colors.bgPrimary)
    }

    var summary: some View {
        SwapDetailsSummary(detailsViewModel: detailsViewModel)
            .redacted(reason: detailsViewModel.showsQuoteSkeleton ? .placeholder : [])
            // First-load only: show the skeleton instantly (nil animation on the
            // entering edge). On a refresh with a prior quote, stale-while-
            // revalidate keeps the summary visible — no skeleton, no flicker.
            .animation(
                detailsViewModel.showsQuoteSkeleton ? nil : .easeInOut(duration: 0.25),
                value: detailsViewModel.showsQuoteSkeleton
            )
            .animation(.easeInOut(duration: 0.25), value: detailsViewModel.totalFeeString)
    }

    @ViewBuilder
    var continueButton: some View {
        let isFormValid = detailsViewModel.validateForm()
        // Block Continue while the fee estimate is still in flight — the
        // form already has a non-zero fee from the previous quote in that
        // window, but using it advances with stale data. validateForm()
        // doesn't see `isLoadingFees` since it's a screen-local concern.
        let isDisabled = !isFormValid || detailsViewModel.isLoading || detailsViewModel.isLoadingFees

        if detailsViewModel.isLoadingTransaction {
            ButtonLoader()
                .disabled(true)
                .opacity(isFormValid ? 1 : 0.5)
        } else {
            PrimaryButton(title: continueButtonTitle) {
                guard let transaction = detailsViewModel.makeTransaction() else { return }
                let retrySignal = SwapRetrySignal()
                router.navigate(to: SwapRoute.verify(
                    transaction: transaction,
                    retrySignal: retrySignal,
                    vaultPubKeyECDSA: vault.pubKeyECDSA
                ))
            }
            .disabled(isDisabled)
            .opacity(isFormValid ? 1 : 0.5)
        }
    }

    /// The Continue button stays disabled at insufficient balance; when a quote
    /// is present we surface the insufficiency on the button label itself rather
    /// than blocking the quote preview with an error tooltip.
    var continueButtonTitle: String {
        if detailsViewModel.balanceError != nil, detailsViewModel.quote != nil {
            return String(format: "swapInsufficientTokenBalance".localized, detailsViewModel.fromCoin.ticker)
        }
        return "continue"
    }

    @ViewBuilder
    var refreshCounter: some View {
        // When the Market/Limit tab row is visible (limit swap enabled) the
        // countdown lives in that row via `tabRowCountdown`; keep the toolbar
        // counter only for the flag-off market layout, which has no tab row.
        if !settingsViewModel.limitSwapEnabled, detailsViewModel.showRefreshCounter {
            SwapRefreshQuoteCounter(timer: detailsViewModel.timer)
        }
    }

    /// Source coin the **limit** entry seeds with. The shared market default
    /// sorts alphabetically (lands on RUNE), which reads as an untradeable
    /// RUNE→BTC default; prefer a high-value routable native source the vault
    /// holds (BTC → ETH) that doesn't collide with the target. Limit-entry only
    /// — the shared market `detailsViewModel.fromCoin` is unchanged.
    private var limitInitialFromCoin: Coin {
        limitDefaultSourceCoin(
            marketDefault: detailsViewModel.fromCoin,
            targetCoin: detailsViewModel.toCoin,
            vaultCoins: vault.coins
        )
    }

    /// Quote-refresh countdown in the Market/Limit tab row. Market mode only —
    /// it feeds `SwapDetailsViewModel.timer`. Limit orders execute at a fixed
    /// target price, so there is no live quote to count down to.
    @ViewBuilder
    var tabRowCountdown: some View {
        if selectedSwapMode == .market, detailsViewModel.showRefreshCounter {
            SwapQuoteCountdownBadge(seconds: detailsViewModel.timer)
        }
    }

    var advancedSettingsButton: some View {
        ToolbarButton(image: "sliders", type: .outline) {
            handleAdvancedSettingsTap()
        }
        .accessibilityLabel("advancedSettings".localized)
    }

    private func handleAdvancedSettingsTap() {
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
                    detailsViewModel.snapshotAdvancedSettings()
                    detailsViewModel.showAdvancedSettingsSheet = true
                }
            )
        }
    }

    /// Bridges the boolean sheet flag to the `VultDiscountTier?` binding
    /// `TierGatedTap` expects: any non-nil tier means "locked", surfaced as the
    /// single `LockedFeatureSheet(.swapAdvancedSettings)`.
    private var lockedSheetBinding: Binding<VultDiscountTier?> {
        Binding(
            get: { showAdvancedLockedSheet ? .silver : nil },
            set: { showAdvancedLockedSheet = $0 != nil }
        )
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 8) {
                swapContent
                    #if os(macOS)
                    // Keep the error tooltip overlay above the later sibling
                    // percentage buttons, which would otherwise paint on top.
                    .zIndex(1)
                    #endif
                #if os(iOS)
                summary
                #else
                percentageButtons
                summary
                #endif
            }
            #if os(macOS)
            .padding(.horizontal, 16)
            #endif
        }
        #if os(iOS)
        .refreshable {
            detailsViewModel.refreshData(vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
        .toolbar {
            if detailsViewModel.showPercentageButtons {
                ToolbarItemGroup(placement: .keyboard) {
                    percentageButtons

                    Spacer()

                    Button {
                        hideKeyboard()
                    } label: {
                        Text("done".localized)
                    }
                }
            }
        }
        #else
        .scrollClipDisabled()
        #endif
    }

    var percentageButtons: some View {
        @Bindable var vm = detailsViewModel
        return SwapPercentageButtons(
            show100: !detailsViewModel.fromCoin.isNativeToken,
            showAllPercentageButtons: $vm.showAllPercentageButtons
        ) { percentage in
            handlePercentageSelection(percentage)
        }
        #if os(iOS)
        .opacity(keyboardObserver.keyboardHeight == 0 ? 0 : 1)
        .animation(.easeInOut, value: keyboardObserver.keyboardHeight)
        #endif
    }

    private func setData() {
        referredViewModel.setData()
        detailsViewModel.fromChain = detailsViewModel.fromCoin.chain
        detailsViewModel.toChain = detailsViewModel.toCoin.chain
    }

    private func handleSwapTap() {
        detailsViewModel.error = nil
        detailsViewModel.switchCoins(vault: vault, referredCode: referredViewModel.savedReferredCode)
        let fromChain = detailsViewModel.fromChain
        detailsViewModel.fromChain = detailsViewModel.toChain
        detailsViewModel.toChain = fromChain
    }
}

extension SwapDetailsScreen {
    func handlePercentageSelection(_ percentage: Int) {
        detailsViewModel.showAllPercentageButtons = false
        let decimalsToUse: Int = 4

        switch percentage {
        case 25:
            let amount = (detailsViewModel.fromCoin.balanceDecimal / 4).truncated(toPlaces: decimalsToUse)
            detailsViewModel.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            detailsViewModel.updateFromAmount(vault: vault, referredCode: referredViewModel.savedReferredCode, immediate: true)
        case 50:
            let amount = (detailsViewModel.fromCoin.balanceDecimal / 2).truncated(toPlaces: decimalsToUse)
            detailsViewModel.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            detailsViewModel.updateFromAmount(vault: vault, referredCode: referredViewModel.savedReferredCode, immediate: true)
        case 75:
            let amount = (detailsViewModel.fromCoin.balanceDecimal * 3 / 4).truncated(toPlaces: decimalsToUse)
            detailsViewModel.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            detailsViewModel.updateFromAmount(vault: vault, referredCode: referredViewModel.savedReferredCode, immediate: true)
        case 100:
            let fromCoin = detailsViewModel.fromCoin
            if fromCoin.isNativeToken {
                let fee = detailsViewModel.fee
                let amountLessFee = fromCoin.rawBalance.toBigInt() - fee
                let amountLessFeeDecimal = amountLessFee.toDecimal(decimals: fromCoin.decimals) / pow(10, fromCoin.decimals)
                let amount = amountLessFeeDecimal.truncated(toPlaces: decimalsToUse)
                detailsViewModel.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            } else {
                let amount = fromCoin.balanceDecimal.truncated(toPlaces: decimalsToUse)
                detailsViewModel.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            }
            detailsViewModel.updateFromAmount(vault: vault, referredCode: referredViewModel.savedReferredCode, immediate: true)
        default:
            break
        }
    }

    // MARK: - Market / Limit tabs

    /// Toggle between Market and Limit swap modes. Limit is enabled only
    /// when both selected coins live on a THORChain-routable chain. Tap-
    /// changes are local; no router navigation here — the Limit branch
    /// is hosted inline in `body` to feel like a tab, not a push.
    var swapModeTabs: some View {
        SegmentedControl(
            selection: $selectedSwapMode,
            items: [
                SegmentedControlItem(
                    value: SwapFormMode.market,
                    title: "swap.tab.market".localized
                ),
                SegmentedControlItem(
                    value: SwapFormMode.limit,
                    title: "swap.tab.limit".localized,
                    isEnabled: canCurrentPairUseLimitSwap
                )
            ]
        )
    }

    /// Limit-mode availability is a vault-level question, not a pair-level
    /// one: the user may currently be looking at a non-routable pair but
    /// still have THORChain-routable chains enabled on the vault that they
    /// can pick once they switch tabs. Disable Limit only when the vault
    /// has zero routable chains at all — there's nothing to limit-swap.
    /// The picker filter inside `LimitSwapEntryView` re-applies the
    /// per-side routable filter (via `vm.supportedChains`) once Limit is
    /// open.
    private var canCurrentPairUseLimitSwap: Bool {
        vault.chains.contains(where: { isThorchainRoutable(chain: $0) })
    }
}
