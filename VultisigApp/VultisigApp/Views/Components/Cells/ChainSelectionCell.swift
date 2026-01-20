//
//  ChainSelectionCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct ChainSelectionCell: View {
    let assets: [CoinMeta]
    @Binding var showAlert: Bool
    
    @State var isSelected = false
    @State var selectedTokensCount = 0
    @EnvironmentObject var tokenSelectionViewModel: CoinSelectionViewModel
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
            .onChange(of: tokenSelectionViewModel.selection) { _, _ in
                setData()
            }
    }
    
    var content: some View {
        ZStack {
            
            // This allow to remove the chains even with tokens
            enabledContent
            
        }
    }
    
    var enabledContent: some View {
        cell
    }
    
    var cell: some View {
        let nativeAsset = assets[0]
        return CoinSelectionCell(asset: nativeAsset)
    }
    
    private func setData() {
        guard let nativeAsset = assets.first else {
            return
        }
        
        if tokenSelectionViewModel.selection.contains(where: { cm in
            cm.chain == nativeAsset.chain && cm.ticker.lowercased() == nativeAsset.ticker.lowercased()
        }) {
            isSelected = true
        } else {
            isSelected = false
        }
        
        countSelectedToken()
    }
    
    private func countSelectedToken() {
        selectedTokensCount = 0
        for asset in assets {
            if tokenSelectionViewModel.selection.contains(where: { cm in
                cm.chain == asset.chain && cm.ticker.lowercased() == asset.ticker.lowercased()
            }) {
                selectedTokensCount += 1
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        ChainSelectionCell(assets: [], showAlert: .constant(false))
    }
    .environmentObject(CoinSelectionViewModel())
}
