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
                list
            }
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

    /// The rounded surface belongs to the rows, not to the scroll viewport: a
    /// `ScrollView` fills the height it is offered, so rounding it left the
    /// bottom corners at the bottom of the sheet and the last row square.
    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                SwapCoinCell(
                    coin: destination.asset,
                    balance: nil,
                    balanceFiat: nil,
                    isSelected: destination == selected,
                    showsSeparator: false
                ) {
                    onSelect(destination)
                }
                .commonListItemContainer(index: index, itemsCount: destinations.count)
            }
        }
        .commonListContainer()
    }
}
