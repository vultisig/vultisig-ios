//
//  SwapCryptoDetailsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-07.
//

#if os(iOS)
import SwiftUI

extension SwapCryptoDetailsView {
    var container: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
            percentageButtons
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
                showSheet: $swapViewModel.showFromCoinSelector,
                selectedCoin: $tx.fromCoin,
                selectedChain: $swapViewModel.fromChain,
                isLoading: swapViewModel.isLoading
            )
        })
        .sheet(isPresented: $swapViewModel.showToCoinSelector, content: {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $swapViewModel.showToCoinSelector,
                selectedCoin: $tx.toCoin,
                selectedChain: $swapViewModel.toChain,
                isLoading: swapViewModel.isLoading
            )
        })
    }
    
    var view: some View {
       content
            .toolbar {
                ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                    refreshCounter
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    
                    Button {
                        hideKeyboard()
                    } label: {
                        Text(NSLocalizedString("done", comment: "Done"))
                    }
                }
            }
    }
    
    var percentageButtons: some View {
        SwapPercentageButtons(
            show100: !tx.fromCoin.isNativeToken,
            showAllPercentageButtons: $swapViewModel.showAllPercentageButtons
        ) { percentage in
            handlePercentageSelection(percentage)
        }
        .opacity(keyboardObserver.keyboardHeight == 0 ? 0 : 1)
        .offset(y: -0.9 * CGFloat(keyboardObserver.keyboardHeight))
        .animation(.easeInOut, value: keyboardObserver.keyboardHeight)
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 8) {
                swapContent
                summary
            }
            .padding(.horizontal, 16)
        }
        .refreshable {
            swapViewModel.refreshData(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
    }
}
#endif
