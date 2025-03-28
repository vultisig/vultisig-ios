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
        ZStack(alignment: .bottom) {
            Background()
            view
            
            if swapViewModel.isLoading {
                loader
            }
        }
    }
    
    var view: some View {
       content
            .padding(.horizontal, 25)
    }
    
    var percentageButtons: some View {
        SwapPercentageButtons(
            tx: tx,
            swapViewModel: swapViewModel
        )
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 8) {
                swapContent
//                percentageButtons
                summary
            }
            .padding(.horizontal, 16)
        }
    }
}
#endif
