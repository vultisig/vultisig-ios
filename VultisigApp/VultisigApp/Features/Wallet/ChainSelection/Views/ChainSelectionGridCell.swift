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
    
    @State var isSelected = false
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    var nativeAsset: CoinMeta {
        assets[0]
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
        .onAppear(perform: onAppear)
    }
    
    func onAppear() {
        guard let nativeAsset = assets.first else {
            return
        }
        
        if viewModel.selection.contains(where: { cm in
            cm.chain == nativeAsset.chain && cm.ticker.lowercased() == nativeAsset.ticker.lowercased()
        }) {
            isSelected = true
        } else {
            isSelected = false
        }
    }
}

#Preview {
    ChainSelectionGridCell(assets: [.example]) { _ in }
        .environmentObject(CoinSelectionViewModel())
    
}
