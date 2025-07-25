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
    @State var isFromPickerActive = false
    @State var isToPickerActive = false
    
    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var keyboardObserver = KeyboardObserver()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let vault: Vault

    var body: some View {
        container
            .onAppear {
                setData()
            }
            .onReceive(timer) { input in
                swapViewModel.updateTimer(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
            }
            .onChange(of: tx.fromCoin, { oldValue, newValue in
                handleFromCoinUpdate()
            })
            .onChange(of: tx.toCoin, { oldValue, newValue in
                handleToCoinUpdate()
            })
            .navigationDestination(isPresented: $isFromPickerActive) {
                CoinPickerView(coins: swapViewModel.pickerFromCoins(tx: tx)) { coin in
                    swapViewModel.updateFromCoin(coin: coin, tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
                    swapViewModel.updateCoinLists(tx: tx)
                }
            }
            .navigationDestination(isPresented: $isToPickerActive) {
                CoinPickerView(coins: swapViewModel.pickerToCoins(tx: tx)) { coin in
                    swapViewModel.updateToCoin(coin: coin, tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
                }
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
            swapButton
            
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
        .padding(8)
        .background(Color.backgroundBlue)
        .cornerRadius(60)
        .overlay(
            Circle()
                .stroke(Color.blue400, lineWidth: 1)
        )
    }
    
    var swapLabel: some View {
        Group {
            if swapViewModel.isLoadingQuotes {
                // Show loader instead of swap icon when loading
                SpinningLineLoader()
                    .scaleEffect(0.8)
                    .frame(width: 38, height: 38)
            } else {
                // Show swap icon when not loading
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body16MontserratMedium)
                    .foregroundColor(.neutral0)
                    .frame(width: 38, height: 38)
            }
        }
        .background(Color.persianBlue400)
        .cornerRadius(50)
        .padding(2)
        .background(Color.black.opacity(0.2))
        .cornerRadius(50)
        .rotationEffect(.degrees(buttonRotated ? 180 : 0))
        .animation(.spring, value: buttonRotated)
    }
    
    var filler: some View {
        Rectangle()
            .frame(width: 12, height: 10)
            .foregroundColor(Color.backgroundBlue)
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
                .padding(40)
        } else {
            PrimaryButton(title: "continue") {
                Task {
                    swapViewModel.moveToNextView()
                }
            }
            .disabled(isDisabled)
            .opacity(swapViewModel.validateForm(tx: tx) ? 1 : 0.5)
            .padding(40)
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
        swapViewModel.refreshData(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
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
            tx.fromAmount = (tx.fromCoin.balanceDecimal * 0.25).formatToDecimal(digits: decimalsToUse)
            handleFromCoinUpdate()
        case 50:
            tx.fromAmount = (tx.fromCoin.balanceDecimal * 0.5).formatToDecimal(digits: decimalsToUse)
            handleFromCoinUpdate()
        case 75:
            tx.fromAmount = (tx.fromCoin.balanceDecimal * 0.75).formatToDecimal(digits: decimalsToUse)
            handleFromCoinUpdate()
        case 100:
            tx.fromAmount = tx.fromCoin.balanceDecimal.formatToDecimal(digits: decimalsToUse)
            handleFromCoinUpdate()
            let amountLessFee = tx.fromCoin.rawBalance.toBigInt() - tx.fee
            let amountLessFeeDecimal = amountLessFee.toDecimal(decimals: tx.fromCoin.decimals) / pow(10, tx.fromCoin.decimals)
            tx.fromAmount = amountLessFeeDecimal.formatToDecimal(digits: decimalsToUse)
        default:
            break
        }
    }
}

#Preview {
    SwapCryptoDetailsView(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel(), vault: .example)
}
