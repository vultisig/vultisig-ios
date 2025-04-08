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

            if swapViewModel.isLoading {
                loader
            }
        }
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
        SwapPercentageButtons { percentage in
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
            swapViewModel.refreshData(tx: tx, vault: vault)
        }
    }
}
#endif
