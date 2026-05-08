//
//  SwapDetailsScreen.swift
//  VultisigApp
//

import SwiftUI

struct SwapDetailsScreen: View {
    let fromCoin: Coin?
    let toCoin: Coin?
    let vault: Vault

    @StateObject var tx = SwapTransaction()
    @StateObject var detailsViewModel = SwapDetailsViewModel()
    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var keyboardObserver = KeyboardObserver()

    @State var buttonRotated = false
    @State var showErrorTooltip = false

    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @Environment(\.router) var router

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
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
        .crossPlatformSheet(isPresented: $detailsViewModel.showFromChainSelector) {
            SwapChainPickerView(
                filterType: .swap,
                vault: vault,
                showSheet: $detailsViewModel.showFromChainSelector,
                selectedChain: $detailsViewModel.fromChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $detailsViewModel.showToChainSelector) {
            SwapChainPickerView(
                filterType: .swap,
                vault: vault,
                showSheet: $detailsViewModel.showToChainSelector,
                selectedChain: $detailsViewModel.toChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $detailsViewModel.showFromCoinSelector) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $detailsViewModel.showFromCoinSelector,
                selectedCoin: $tx.fromCoin,
                selectedChain: detailsViewModel.fromChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $detailsViewModel.showToCoinSelector) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $detailsViewModel.showToCoinSelector,
                selectedCoin: $tx.toCoin,
                selectedChain: detailsViewModel.toChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .onLoad {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            detailsViewModel.load(
                initialFromCoin: fromCoin,
                initialToCoin: toCoin,
                vault: vault,
                tx: tx
            )
            if let fromCoin {
                tx.fromCoin = fromCoin
            }
            setData()
        }
        .task {
            await detailsViewModel.loadFastVault(tx: tx, vault: vault)
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .onReceive(timer) { _ in
            detailsViewModel.updateTimer(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
        .onChange(of: tx.fromCoin) { _, _ in
            detailsViewModel.updateFromCoin(coin: tx.fromCoin, tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
        .onChange(of: tx.toCoin) { _, _ in
            detailsViewModel.updateToCoin(coin: tx.toCoin, tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
        .onChange(of: detailsViewModel.fromChain) { _, _ in
            detailsViewModel.handleFromChainUpdate(tx: tx, vault: vault)
        }
        .onChange(of: detailsViewModel.toChain) { _, _ in
            detailsViewModel.handleToChainUpdate(tx: tx, vault: vault)
        }
        .onChange(of: detailsViewModel.error?.localizedDescription) { _, newError in
            showErrorTooltip = newError != nil
        }
        .onChange(of: tx.fromAmount) { _, _ in
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
        SwapFromToField(
            title: "from",
            vault: vault,
            coin: tx.fromCoin,
            fiatAmount: SwapCryptoLogic.fromFiatAmount(tx: tx),
            amount: $tx.fromAmount,
            selectedChain: $detailsViewModel.fromChain,
            showNetworkSelectSheet: $detailsViewModel.showFromChainSelector,
            showCoinSelectSheet: $detailsViewModel.showFromCoinSelector,
            tx: tx,
            detailsViewModel: detailsViewModel,
            handlePercentageSelection: handlePercentageSelection
        )
    }

    var swapToField: some View {
        SwapFromToField(
            title: "to",
            vault: vault,
            coin: tx.toCoin,
            fiatAmount: SwapCryptoLogic.toFiatAmount(tx: tx),
            amount: .constant(tx.toAmountDecimal.formatForDisplay()),
            selectedChain: $detailsViewModel.toChain,
            showNetworkSelectSheet: $detailsViewModel.showToChainSelector,
            showCoinSelectSheet: $detailsViewModel.showToCoinSelector,
            tx: tx,
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
        SwapDetailsSummary(tx: tx, detailsViewModel: detailsViewModel)
            .redacted(reason: detailsViewModel.isLoadingQuotes ? .placeholder : [])
    }

    @ViewBuilder
    var continueButton: some View {
        let isDisabled = !SwapCryptoLogic.validateForm(tx: tx, isLoading: detailsViewModel.isLoading) || detailsViewModel.isLoading

        if detailsViewModel.isLoadingTransaction {
            ButtonLoader()
                .disabled(true)
                .opacity(SwapCryptoLogic.validateForm(tx: tx, isLoading: detailsViewModel.isLoading) ? 1 : 0.5)
        } else {
            PrimaryButton(title: "continue") {
                router.navigate(to: SwapRoute.verify(tx: tx, vault: vault))
            }
            .disabled(isDisabled)
            .opacity(SwapCryptoLogic.validateForm(tx: tx, isLoading: detailsViewModel.isLoading) ? 1 : 0.5)
        }
    }

    var refreshCounter: some View {
        SwapRefreshQuoteCounter(timer: detailsViewModel.timer)
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
            detailsViewModel.refreshData(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
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
                        Text(NSLocalizedString("done", comment: "Done"))
                    }
                }
            }
        }
        #else
        .scrollClipDisabled()
        #endif
    }

    var percentageButtons: some View {
        SwapPercentageButtons(
            show100: !tx.fromCoin.isNativeToken,
            showAllPercentageButtons: $detailsViewModel.showAllPercentageButtons
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
        detailsViewModel.fromChain = tx.fromCoin.chain
        detailsViewModel.toChain = tx.toCoin.chain
    }

    private func handleSwapTap() {
        detailsViewModel.error = nil
        buttonRotated.toggle()
        detailsViewModel.switchCoins(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
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
            let amount = (tx.fromCoin.balanceDecimal / 4).truncated(toPlaces: decimalsToUse)
            tx.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            detailsViewModel.updateFromAmount(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        case 50:
            let amount = (tx.fromCoin.balanceDecimal / 2).truncated(toPlaces: decimalsToUse)
            tx.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            detailsViewModel.updateFromAmount(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        case 75:
            let amount = (tx.fromCoin.balanceDecimal * 3 / 4).truncated(toPlaces: decimalsToUse)
            tx.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            detailsViewModel.updateFromAmount(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        case 100:
            if tx.fromCoin.isNativeToken {
                let amountLessFee = tx.fromCoin.rawBalance.toBigInt() - tx.fee
                let amountLessFeeDecimal = amountLessFee.toDecimal(decimals: tx.fromCoin.decimals) / pow(10, tx.fromCoin.decimals)
                let amount = amountLessFeeDecimal.truncated(toPlaces: decimalsToUse)
                tx.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            } else {
                let amount = tx.fromCoin.balanceDecimal.truncated(toPlaces: decimalsToUse)
                tx.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            }
            detailsViewModel.updateFromAmount(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        default:
            break
        }
    }
}
