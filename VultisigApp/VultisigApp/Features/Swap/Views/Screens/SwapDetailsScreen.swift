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

    @State private var buttonRotated = false
    @State private var showErrorTooltip = false

    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @Environment(\.router) var router

    var body: some View {
        @Bindable var vm = detailsViewModel
        Screen {
            VStack {
                fields
                continueButton
            }
        }
        .screenTitle("swap".localized)
        .screenToolbar {
            CustomToolbarItem(placement: .trailing, hideSharedBackground: true) {
                refreshCounter
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

            if let error = detailsViewModel.error {
                SwapErrorTooltipView(
                    error: error,
                    showTooltip: $showErrorTooltip,
                    onDismissTooltip: {
                        showErrorTooltip = false
                    }
                )
            } else {
                swapButton
            }

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

    var swapButton: some View {
        Button {
            handleSwapTap()
        } label: {
            swapLabel
        }
        .background(Circle().fill(Theme.colors.bgPrimary))
        .overlay(Circle().stroke(Theme.colors.bgSurface2))
    }

    var swapLabel: some View {
        ZStack {
            if detailsViewModel.isLoadingQuotes {
                CircularProgressIndicator(size: 20)
            } else {
                Icon(named: "arrow-bottom-top", color: Theme.colors.textPrimary, size: 18)
            }
        }
        .frame(width: 34, height: 34)
        .background(Circle().fill(Theme.colors.bgButtonTertiary))
        .padding(2)
        .background(Circle().fill(Theme.colors.bgPrimary))
        .rotationEffect(.degrees(buttonRotated ? 180 : 0))
        .animation(.spring, value: buttonRotated)
    }

    var filler: some View {
        Rectangle()
            .frame(width: 12, height: 10)
            .foregroundColor(Theme.colors.bgPrimary)
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
            PrimaryButton(title: "continue") {
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

    @ViewBuilder
    var refreshCounter: some View {
        if detailsViewModel.showRefreshCounter {
            SwapRefreshQuoteCounter(timer: detailsViewModel.timer)
        }
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 8) {
                swapContent
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
            if !detailsViewModel.showFromChainSelector
                && !detailsViewModel.showToChainSelector
                && !detailsViewModel.showFromCoinSelector
                && !detailsViewModel.showToCoinSelector {
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
        buttonRotated.toggle()
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
}
