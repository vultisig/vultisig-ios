//
//  IBCDestinationSelectionScreen.swift
//  VultisigApp
//
//  The destination-chain picker. Each row is the destination chain's native
//  asset, which is what an IBC transfer actually arrives as, rendered by the
//  same cell the swap and asset pickers use.
//
//  The route set is static per source chain — there is nothing to fetch, so no
//  loading or empty state here; a source chain with no routes never opens this
//  sheet (the form says so instead).
//

import SwiftUI

struct IBCDestinationSelectionScreen: View {
    @Binding var isPresented: Bool
    let destinations: [IBCDestination]
    let selected: IBCDestination?
    var onSelect: (IBCDestination) -> Void

    var body: some View {
        Screen {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(destinations) { destination in
                        SwapCoinCell(
                            coin: destination.asset,
                            balance: nil,
                            balanceFiat: nil,
                            isSelected: destination == selected
                        ) {
                            onSelect(destination)
                        }
                    }
                }
            }
            .cornerRadius(Theme.radius.xl)
        }
        .screenTitle("selectDestinationChain".localized)
        .screenBackButtonHidden()
        .screenToolbar {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark) {
                    isPresented = false
                }
            }
        }
        .applySheetSize()
        .sheetStyle()
    }
}
