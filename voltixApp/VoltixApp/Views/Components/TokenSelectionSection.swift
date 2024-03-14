//
//  TokenSelectionSection.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct TokenSelectionSection: View {
    let title: String
    let assets: [Asset]
    
    var body: some View {
        VStack {
            header
            cells
        }
    }
    
    var header: some View {
        Text(title)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var cells: some View {
        VStack(spacing: 12) {
            ForEach(assets, id: \.self) { asset in
                TokenCell(asset: asset)
            }
        }
    }
}

#Preview {
    TokenSelectionSection(title: "Bitcoin", assets: [Asset.example])
}
