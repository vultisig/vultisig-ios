//
//  ChainSelectionCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct ChainSelectionCell: View {
    let title: String
    let assets: [Coin]
    
    var body: some View {
        VStack {
            header
            cell
        }
    }
    
    var header: some View {
        Text(title)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var cell: some View {
        let nativeAsset = assets.first
        
        return TokenSelectionCell(asset: nativeAsset ?? Coin.example)
            .redacted(reason: nativeAsset==nil ? .placeholder : [])
    }
}

#Preview {
    ZStack {
        Background()
        ChainSelectionCell(title: "Bitcoin", assets: [])
    }
}
