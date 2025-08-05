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
                MacOSOverlay()
                    .onTapGesture(perform: closeSheets)
            }
            
            VStack {
                if swapViewModel.showFromChainSelector {
                    SwapChainPickerView(
                        filterType: .swap,
                        vault: vault,
                        showSheet: $swapViewModel.showFromChainSelector,
                        selectedChain: $swapViewModel.fromChain
                    )
                }
                
                if swapViewModel.showToChainSelector {
                    SwapChainPickerView(
                        filterType: .swap,
                        vault: vault,
                        showSheet: $swapViewModel.showToChainSelector,
                        selectedChain: $swapViewModel.toChain
                    )
                }
                
                if swapViewModel.showFromCoinSelector {
                    SwapCoinPickerView(
                        vault: vault,
                        showSheet: $swapViewModel.showFromCoinSelector,
                        selectedCoin: $tx.fromCoin,
                        selectedChain: swapViewModel.fromChain
                    )
                }
                
                if swapViewModel.showToCoinSelector {
                    SwapCoinPickerView(
                        vault: vault,
                        showSheet: $swapViewModel.showToCoinSelector,
                        selectedCoin: $tx.toCoin,
                        selectedChain: swapViewModel.toChain
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
        SwapPercentageButtons(
            show100: !tx.fromCoin.isNativeToken,
            showAllPercentageButtons: $swapViewModel.showAllPercentageButtons
        ) { percentage in
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
    
    func closeSheets() {
        swapViewModel.showFromChainSelector = false
        swapViewModel.showToChainSelector = false
        swapViewModel.showFromCoinSelector = false
        swapViewModel.showToCoinSelector = false
    }
}
#endif
