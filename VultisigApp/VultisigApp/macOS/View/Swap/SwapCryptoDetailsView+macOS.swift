//
//  SwapCryptoDetailsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-07.
//

#if os(macOS)
import SwiftUI

extension SwapCryptoDetailsView {
    var container: some View {
        ZStack(alignment: .top) {
            Background()
            view
            
            if showSheet() {
                overlay
            }
            
            VStack {
                if swapViewModel.showFromChainSelector {
                    SwapChainPickerView(
                        vault: vault,
                        showSheet: $swapViewModel.showFromChainSelector,
                        selectedChain: $swapViewModel.fromChain,
                        selectedCoin: $tx.fromCoin
                    )
                }
                
                if swapViewModel.showToChainSelector {
                    SwapChainPickerView(
                        vault: vault,
                        showSheet: $swapViewModel.showToChainSelector,
                        selectedChain: $swapViewModel.toChain,
                        selectedCoin: $tx.toCoin
                    )
                }
                
                if swapViewModel.showFromCoinSelector {
                    SwapCoinPickerView(
                        vault: vault,
                        showSheet: $swapViewModel.showFromCoinSelector,
                        selectedCoin: $tx.fromCoin,
                        selectedChain: $swapViewModel.fromChain,
                        isLoading: swapViewModel.isLoading
                    )
                }
                
                if swapViewModel.showToCoinSelector {
                    SwapCoinPickerView(
                        vault: vault,
                        showSheet: $swapViewModel.showToCoinSelector,
                        selectedCoin: $tx.toCoin,
                        selectedChain: $swapViewModel.toChain,
                        isLoading: swapViewModel.isLoading
                    )
                }
            }
        }
    }
    
    var view: some View {
       content
            .padding(.horizontal, 25)
    }
    
    var percentageButtons: some View {
        SwapPercentageButtons(showAllPercentageButtons: $swapViewModel.showAllPercentageButtons) { percentage in
            handlePercentageSelection(percentage)
        }
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 8) {
                swapContent
                percentageButtons
                summary
            }
            .padding(.horizontal, 16)
        }
    }
    
    var overlay: some View {
        ZStack(alignment: .top) {
            Color.black
                .frame(height: 200)
                .offset(y: -200)
            
            Color.black
        }
        .opacity(0.8)
        .onTapGesture {
            closeSheets()
        }
    }
    
    func closeSheets() {
        swapViewModel.showFromChainSelector = false
        swapViewModel.showToChainSelector = false
        swapViewModel.showFromCoinSelector = false
        swapViewModel.showToCoinSelector = false
    }
}
#endif
