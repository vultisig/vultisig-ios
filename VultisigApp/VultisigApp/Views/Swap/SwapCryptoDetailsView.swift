//
//  SwapCryptoDetailsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoDetailsView: View {
    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel

    @State var buttonRotated = false
    @State var showErrorTooltip = false

    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var keyboardObserver = KeyboardObserver()

    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let vault: Vault

    var body: some View {
        screenContainer
            .onAppear {
                setData()
            }
            .onReceive(timer) { _ in
                swapViewModel.updateTimer(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
            }
            .onChange(of: tx.fromCoin, { _, _ in
                handleFromCoinUpdate()
            })
            .onChange(of: tx.toCoin, { _, _ in
                handleToCoinUpdate()
            })
            .onChange(of: swapViewModel.fromChain) { _, _ in
                swapViewModel.handleFromChainUpdate(tx: tx, vault: vault)
            }
            .onChange(of: swapViewModel.toChain) { _, _ in
                swapViewModel.handleToChainUpdate(tx: tx, vault: vault)
            }
            .onChange(of: swapViewModel.error?.localizedDescription) { _, newError in
                if newError != nil {
                    showErrorTooltip = true
                } else {
                    showErrorTooltip = false
                }
            }
            .onChange(of: tx.fromAmount) { _, _ in
                swapViewModel.error = nil
            }
    }

    var screenContainer: some View {
        ZStack(alignment: .bottom) {
            screenContent
        }
    }

    var screenContent: some View {
        Screen {
            view
        }
        .screenNavigationBarHidden()
        .crossPlatformSheet(isPresented: $swapViewModel.showFromChainSelector) {
            SwapChainPickerView(
                filterType: .swap,
                vault: vault,
                showSheet: $swapViewModel.showFromChainSelector,
                selectedChain: $swapViewModel.fromChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $swapViewModel.showToChainSelector) {
            SwapChainPickerView(
                filterType: .swap,
                vault: vault,
                showSheet: $swapViewModel.showToChainSelector,
                selectedChain: $swapViewModel.toChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $swapViewModel.showFromCoinSelector) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $swapViewModel.showFromCoinSelector,
                selectedCoin: $tx.fromCoin,
                selectedChain: swapViewModel.fromChain
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $swapViewModel.showToCoinSelector) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $swapViewModel.showToCoinSelector,
                selectedCoin: $tx.toCoin,
                selectedChain: swapViewModel.toChain
            )
            .environmentObject(coinSelectionViewModel)
        }
    }

    var content: some View {
        VStack {
            fields
            continueButton
        }
    }

    var swapContent: some View {
        ZStack {
            amountFields

            if let error = swapViewModel.error {
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

            filler
                .offset(x: -28)

            filler
                .offset(x: 28)
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
            fiatAmount: swapViewModel.fromFiatAmount(tx: tx),
            amount: $tx.fromAmount,
            selectedChain: $swapViewModel.fromChain,
            showNetworkSelectSheet: $swapViewModel.showFromChainSelector,
            showCoinSelectSheet: $swapViewModel.showFromCoinSelector,
            tx: tx,
            swapViewModel: swapViewModel,
            handlePercentageSelection: handlePercentageSelection
        )
    }

    var swapToField: some View {
        SwapFromToField(
            title: "to",
            vault: vault,
            coin: tx.toCoin,
            fiatAmount: swapViewModel.toFiatAmount(tx: tx),
            amount: .constant(tx.toAmountDecimal.formatForDisplay()),
            selectedChain: $swapViewModel.toChain,
            showNetworkSelectSheet: $swapViewModel.showToChainSelector,
            showCoinSelectSheet: $swapViewModel.showToCoinSelector,
            tx: tx,
            swapViewModel: swapViewModel,
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
            if swapViewModel.isLoadingQuotes {
                // Show loader instead of swap icon when loading
                CircularProgressIndicator(size: 20)
            } else {
                // Show swap icon when not loading
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
        SwapDetailsSummary(tx: tx, swapViewModel: swapViewModel)
            .redacted(reason: swapViewModel.isLoadingQuotes ? .placeholder : [])
    }

    @ViewBuilder
    var continueButton: some View {
        let isDisabled = !swapViewModel.validateForm(tx: tx) || swapViewModel.isLoading

        if swapViewModel.isLoadingTransaction {
            ButtonLoader()
                .disabled(true)
                .opacity(swapViewModel.validateForm(tx: tx) ? 1 : 0.5)
        } else {
            PrimaryButton(title: "continue") {
                Task {
                    swapViewModel.moveToNextView()
                }
            }
            .disabled(isDisabled)
            .opacity(swapViewModel.validateForm(tx: tx) ? 1 : 0.5)
        }
    }

    var loader: some View {
        VStack {
            Spacer()
            Loader()
            Spacer()
        }
    }

    var refreshCounter: some View {
        SwapRefreshQuoteCounter(timer: swapViewModel.timer)
    }

    private func setData() {
        referredViewModel.setData()
        swapViewModel.fromChain = tx.fromCoin.chain
        swapViewModel.toChain = tx.toCoin.chain
    }

    private func handleFromCoinUpdate() {
        swapViewModel.updateFromCoin(coin: tx.fromCoin, tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
    }

    private func handleToCoinUpdate() {
        swapViewModel.updateToCoin(coin: tx.toCoin, tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
    }

    private func handleSwapTap() {
        swapViewModel.error = nil
        buttonRotated.toggle()
        swapViewModel.switchCoins(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        let fromChain = swapViewModel.fromChain
        swapViewModel.fromChain = swapViewModel.toChain
        swapViewModel.toChain = fromChain
    }

    func showSheet() -> Bool {
        swapViewModel.showFromChainSelector || swapViewModel.showToChainSelector || swapViewModel.showFromCoinSelector || swapViewModel.showToCoinSelector
    }
}

extension SwapCryptoDetailsView {
    public func handlePercentageSelection(_ percentage: Int) {
        swapViewModel.showAllPercentageButtons = false
        // We use 4 decimals to avoid impractical precision
        // Also LIFI and other providers use 4 decimals top
        let decimalsToUse: Int = 4

        switch percentage {
        case 25:
            let amount = (tx.fromCoin.balanceDecimal / 4).truncated(toPlaces: decimalsToUse)
            tx.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            swapViewModel.updateFromAmount(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        case 50:
            let amount = (tx.fromCoin.balanceDecimal / 2).truncated(toPlaces: decimalsToUse)
            tx.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            swapViewModel.updateFromAmount(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        case 75:
            let amount = (tx.fromCoin.balanceDecimal * 3 / 4).truncated(toPlaces: decimalsToUse)
            tx.fromAmount = amount.formatToDecimal(digits: decimalsToUse)
            swapViewModel.updateFromAmount(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
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
            swapViewModel.updateFromAmount(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        default:
            break
        }
    }
}

#Preview {
    SwapCryptoDetailsView(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel(), vault: .example)
}
