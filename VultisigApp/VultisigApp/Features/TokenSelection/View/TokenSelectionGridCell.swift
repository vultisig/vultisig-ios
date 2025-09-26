//
//  TokenSelectionGridCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct TokenSelectionGridCell: View {
    let coin: CoinMeta
    var onSelection: (Bool) -> Void
    
    @State var isSelected: Bool
    
    init(coin: CoinMeta, isSelected: Bool, onSelection: @escaping (Bool) -> Void) {
        self.coin = coin
        self.isSelected = isSelected
        self.onSelection = onSelection
    }
    
    var body: some View {
        AssetSelectionGridCell(
            name: coin.ticker,
            ticker: coin.ticker,
            logo: coin.logo,
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
