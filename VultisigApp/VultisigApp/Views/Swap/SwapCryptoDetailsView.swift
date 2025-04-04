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
    
    @StateObject var keyboardObserver = KeyboardObserver()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let vault: Vault

    var body: some View {
        container
            .onAppear {
                setData()
            }
            .onReceive(timer) { input in
                swapViewModel.updateTimer(tx: tx, vault: vault)
            }
            .onChange(of: tx.fromCoin, { oldValue, newValue in
                handleFromCoinUpdate()
            })
            .onChange(of: tx.toCoin, { oldValue, newValue in
                handleToCoinUpdate()
            })
            .navigationDestination(isPresented: $isFromPickerActive) {
                CoinPickerView(coins: swapViewModel.pickerFromCoins(tx: tx)) { coin in
                    swapViewModel.updateFromCoin(coin: coin, tx: tx, vault: vault)
                    swapViewModel.updateCoinLists(tx: tx)
                }
            }
            .navigationDestination(isPresented: $isToPickerActive) {
                CoinPickerView(coins: swapViewModel.pickerToCoins(tx: tx)) { coin in
                    swapViewModel.updateToCoin(coin: coin, tx: tx, vault: vault)
                }
            }
    }
    
    var content: some View {
        VStack {
            fields
            continueButton
        }
        .sheet(isPresented: $swapViewModel.showFromChainSelector, content: {
            SwapChainPickerView(
                vault: vault,
                showSheet: $swapViewModel.showFromChainSelector,
                selectedChain: $swapViewModel.fromChain,
                selectedCoin: $tx.fromCoin
            )
        })
        .sheet(isPresented: $swapViewModel.showToChainSelector, content: {
            SwapChainPickerView(
                vault: vault,
                showSheet: $swapViewModel.showToChainSelector,
                selectedChain: $swapViewModel.toChain,
                selectedCoin: $tx.toCoin
            )
        })
        .sheet(isPresented: $swapViewModel.showFromCoinSelector, content: {
            SwapCoinPickerView(
                vault: vault,
                selectedNetwork: swapViewModel.fromChain,
                showSheet: $swapViewModel.showFromCoinSelector,
                selectedCoin: $tx.fromCoin,
                selectedChain: $swapViewModel.fromChain
            )
        })
        .sheet(isPresented: $swapViewModel.showToCoinSelector, content: {
            SwapCoinPickerView(
                vault: vault,
                selectedNetwork: swapViewModel.toChain,
                showSheet: $swapViewModel.showToCoinSelector,
                selectedCoin: $tx.toCoin,
                selectedChain: $swapViewModel.toChain
            )
        })
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
            swapViewModel: swapViewModel
        )
    }
    
    var swapToField: some View {
        SwapFromToField(
            title: "to",
            vault: vault,
            coin: tx.toCoin,
            fiatAmount: swapViewModel.toFiatAmount(tx: tx),
            amount: .constant(tx.toAmountDecimal.description),
            selectedChain: $swapViewModel.toChain,
            showNetworkSelectSheet: $swapViewModel.showToChainSelector,
            showCoinSelectSheet: $swapViewModel.showToCoinSelector,
            tx: tx,
            swapViewModel: swapViewModel
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
        Image(systemName: "arrow.up.arrow.down")
            .font(.body16MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(width: 38, height: 38)
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
    }
    
    var continueButton: some View {
        let isDisabled = !swapViewModel.validateForm(tx: tx)
        
        return Button {
            Task {
                swapViewModel.moveToNextView()
            }
        } label: {
            FilledButton(
                title: "continue",
                textColor: isDisabled ? .textDisabled : .blue600,
                background: isDisabled ? .buttonDisabled : .turquoise600
            )
        }
        .disabled(isDisabled)
        .opacity(swapViewModel.validateForm(tx: tx) ? 1 : 0.5)
        .padding(40)
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
        swapViewModel.updateFromCoin(coin: tx.fromCoin, tx: tx, vault: vault)
    }
    
    private func handleToCoinUpdate() {
        swapViewModel.updateToCoin(coin: tx.toCoin, tx: tx, vault: vault)
    }
    
    private func handleSwapTap() {
        buttonRotated.toggle()
        swapViewModel.switchCoins(tx: tx, vault: vault)
        let fromChain = swapViewModel.fromChain
        swapViewModel.fromChain = swapViewModel.toChain
        swapViewModel.toChain = fromChain
    }
}

#Preview {
    SwapCryptoDetailsView(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel(), vault: .example)
}
