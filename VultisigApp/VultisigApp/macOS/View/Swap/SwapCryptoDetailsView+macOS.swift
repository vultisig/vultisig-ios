//
//  SwapCryptoDetailsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-07.
//

#if os(macOS)
import SwiftUI

extension SwapCryptoDetailsView {
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
                    .zIndex(1)
                percentageButtons
                summary
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }
}
#endif
