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

// MARK: - Yield Provider Selection Cell (Circle / Noon)

/// One selection cell for a USDC yield provider (Circle, Noon). The bits that
/// differ between providers — display name, logo, and current enabled state —
/// are passed in, so a single cell serves every provider.
struct DefiYieldSelectionGridCell: View {
    let name: String
    let logo: String
    let isEnabled: Bool
    var onSelection: (Bool) -> Void

    @State var isSelected = false

    var body: some View {
        AssetSelectionGridCell(
            name: name,
            ticker: "USDC",
            logo: logo,
            isSelected: $isSelected
        ) {
            onSelection(isSelected)
        }
        .onAppear { isSelected = isEnabled }
    }
}

#Preview {
    DefiChainSelectionGridCell(
        chain: .thorChain,
        viewModel: DefiSelectChainViewModel()
    ) { _ in }
    .environmentObject(CoinSelectionViewModel())

}
