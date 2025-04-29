//
//  SwapCoinPickerView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-28.
//

#if os(macOS)
import SwiftUI

extension SwapCoinPickerView {
    var body: some View {
        content
            .frame(width: 700, height: 450)
    }
    
    var content: some View {
        ZStack {
            Background()
            main
            
            if showChainPickerSheet {
                SwapChainPickerView(
                    vault: vault,
                    showSheet: $showChainPickerSheet,
                    selectedChain: $selectedChain,
                    selectedCoin: $selectedCoin
                )
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}
#endif
