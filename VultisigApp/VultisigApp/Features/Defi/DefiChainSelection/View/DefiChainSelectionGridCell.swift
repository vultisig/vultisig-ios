//
//  DefiChainSelectionGridCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct DefiChainSelectionGridCell: View {
    let chain: Chain
    @ObservedObject var viewModel: DefiSelectChainViewModel
    var onSelection: (DefiChainSelection) -> Void

    @State var isSelected = false

    var body: some View {
        AssetSelectionGridCell(
            name: chain.name,
            ticker: chain.ticker,
            logo: chain.logo,
            isSelected: $isSelected
        ) {
            onSelection(DefiChainSelection(selected: isSelected, chain: chain))
        }
        .onAppear(perform: onAppear)
    }

    func onAppear() {
        isSelected = viewModel.selection.contains(chain)
    }
}

// MARK: - Circle Selection Cell

struct DefiCircleSelectionGridCell: View {
    @ObservedObject var viewModel: DefiSelectChainViewModel
    var onSelection: (Bool) -> Void

    @State var isSelected = false

    var body: some View {
        AssetSelectionGridCell(
            name: NSLocalizedString("circleTitle", comment: "Circle"),
            ticker: "USDC",
            logo: "circle-logo",
            isSelected: $isSelected
        ) {
            onSelection(isSelected)
        }
        .onAppear(perform: onAppear)
    }

    func onAppear() {
        isSelected = viewModel.isCircleEnabled
    }
}

#Preview {
    DefiChainSelectionGridCell(
        chain: .thorChain,
        viewModel: DefiSelectChainViewModel()
    ) { _ in }
    .environmentObject(CoinSelectionViewModel())

}

