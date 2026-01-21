//
//  TokenSelectionGridCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct TokenSelectionGridCell: View {
    let coin: CoinMeta
    let name: String?
    let showChainIcon: Bool
    var onSelection: (Bool) -> Void

    @State var isSelected: Bool

    init(coin: CoinMeta, name: String? = nil, showChainIcon: Bool = false, isSelected: Bool, onSelection: @escaping (Bool) -> Void) {
        self.coin = coin
        self.name = name
        self.showChainIcon = showChainIcon
        self.isSelected = isSelected
        self.onSelection = onSelection
    }

    var body: some View {
        AssetSelectionGridCell(
            name: name ?? coin.ticker,
            ticker: coin.ticker,
            logo: coin.logo,
            tokenChainLogo: showChainIcon ? coin.chain.logo : nil,
            isSelected: $isSelected
        ) { onSelection(isSelected) }
    }
}

#Preview {
    TokenSelectionGridCell(
        coin: .example,
        isSelected: false
    ) { _ in }
}
