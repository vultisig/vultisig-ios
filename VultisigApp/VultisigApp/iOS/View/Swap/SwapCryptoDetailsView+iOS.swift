//
//  SwapCryptoDetailsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-07.
//

#if os(iOS)
import SwiftUI

extension SwapCryptoDetailsView {
    var view: some View {
       content
            .toolbar {
                toolbarItemWithHiddenBackground(placement: Placement.topBarTrailing.getPlacement()) {
                    refreshCounter
                }
                if !swapViewModel.showFromChainSelector && !swapViewModel.showToChainSelector && !swapViewModel.showFromCoinSelector && !swapViewModel.showToCoinSelector {
                    ToolbarItemGroup(placement: .keyboard) {
                        percentageButtons

                        Spacer()

                        Button {
                            hideKeyboard()
                        } label: {
                            Text(NSLocalizedString("done", comment: "Done"))
                        }
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
        .animation(.easeInOut, value: keyboardObserver.keyboardHeight)
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 8) {
                swapContent
                summary
            }
        }
        .refreshable {
            swapViewModel.refreshData(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
    }
}
#endif
