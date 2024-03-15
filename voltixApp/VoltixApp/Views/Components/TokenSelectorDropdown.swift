//
//  TokenSelectorDropdown.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct TokenSelectorDropdown: View {
    let title: String
    let imageName: String
    let amount: String
    
    var body: some View {
        HStack(spacing: 12) {
            image
            Text(title)
            Spacer()
            
            if !amount.isEmpty {
                Text(amount)
            }
            
            Image(systemName: "chevron.down")
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var image: some View {
        Image(imageName)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(100)
    }
}

#Preview {
    TokenSelectorDropdown(title: "Ethereum", imageName: "eth", amount: "23.3")
}
