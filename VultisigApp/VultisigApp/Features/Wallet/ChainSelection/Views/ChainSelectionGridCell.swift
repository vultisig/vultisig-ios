//
//  ChainSelectionGridCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct ChainSelectionGridCell: View {
    let assets: [CoinMeta]
    var onSelection: (ChainSelection) -> Void

    @EnvironmentObject var viewModel: CoinSelectionViewModel
    @State var isSelected: Bool

    var nativeAsset: CoinMeta {
        assets[0]
    }

    init(assets: [CoinMeta], isSelected: Bool, onSelection: @escaping (ChainSelection) -> Void) {
        self.assets = assets
        self.onSelection = onSelection
        self.isSelected = isSelected
    }

    var body: some View {
        AssetSelectionGridCell(
            name: nativeAsset.chain.name,
            ticker: nativeAsset.ticker,
            logo: nativeAsset.chain.logo,
            isSelected: $isSelected
        ) {
            onSelection(ChainSelection(selected: isSelected, asset: nativeAsset))
        }
    }
}

#Preview {
    ChainSelectionGridCell(assets: [.example], isSelected: false) { _ in }
        .environmentObject(CoinSelectionViewModel())

}
