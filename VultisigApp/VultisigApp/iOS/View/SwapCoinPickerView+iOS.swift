//
//  SwapCoinPickerView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-28.
//

#if os(iOS)
import SwiftUI

extension SwapCoinPickerView {
    var body: some View {
        content
    }
    
    var content: some View {
        ZStack {
            Background()
            main
        }
        .buttonStyle(BorderlessButtonStyle())
        .sheet(isPresented: $showChainPickerSheet, content: {
            SwapChainPickerView(
                vault: vault,
                showSheet: $showChainPickerSheet,
                selectedChain: $selectedChain,
                selectedCoin: $selectedCoin
            )
        })
    }
}
#endif
