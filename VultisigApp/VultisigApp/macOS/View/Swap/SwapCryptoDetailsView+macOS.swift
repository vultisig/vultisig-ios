//
//  SwapCryptoDetailsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-07.
//

#if os(macOS)
import SwiftUI

extension SwapCryptoDetailsView {
   var overlay: some View {
        MacOSOverlay()
            .onTapGesture(perform: closeSheets)
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
