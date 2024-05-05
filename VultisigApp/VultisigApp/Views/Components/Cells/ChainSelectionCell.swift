//
//  ChainSelectionCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct ChainSelectionCell: View {
    let assets: [Coin]
    @Binding var showAlert: Bool
    
    @State var isSelected = false
    @State var selectedTokensCount = 0
    @EnvironmentObject var tokenSelectionViewModel: TokenSelectionViewModel
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
            .onChange(of: tokenSelectionViewModel.selection) { oldValue, newValue in
                setData()
            }
    }
    
    var content: some View {
        ZStack {
            if selectedTokensCount>1, isSelected {
                disabledContent
            } else {
                enabledContent
            }
        }
    }
    
    var enabledContent: some View {
        cell
    }
    
    var disabledContent: some View {
        Button {
            showAlert = true
        } label: {
            cell
                .disabled(true)
        }
    }
    
    var cell: some View {
        let nativeAsset = assets.first
        
        return TokenSelectionCell(asset: nativeAsset ?? Coin.example)
            .redacted(reason: nativeAsset==nil ? .placeholder : [])
    }
    
    private func setData() {
        guard let nativeAsset = assets.first else {
            return
        }
        
        if tokenSelectionViewModel.selection.contains(nativeAsset) {
            isSelected = true
        } else {
            isSelected = false
        }
        
        countSelectedToken()
    }
    
    private func countSelectedToken() {
        selectedTokensCount = 0
        for asset in assets {
            if tokenSelectionViewModel.selection.contains(asset) {
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
    .environmentObject(TokenSelectionViewModel())
}
