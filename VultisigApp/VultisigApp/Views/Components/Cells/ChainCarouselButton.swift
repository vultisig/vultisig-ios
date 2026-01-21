//
//  ChainCarouselButton.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-27.
//

import SwiftUI

struct ChainCarouselButton: View {
    let chain: Chain
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(chain.logo)
                    .resizable()
                    .frame(width: 16, height: 16)
                
                Text(chain.name)
                    .font(.body12BrockmannMedium)
                    .foregroundColor(isSelected ? .neutral0 : .extraLightGray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.blue400 : Color.blue600)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? Color.turquoise600 : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

#Preview {
    HStack {
        ChainCarouselButton(
            chain: .ethereum,
            isSelected: true,
            onTap: {}
        )
        ChainCarouselButton(
            chain: .bitcoin,
            isSelected: false,
            onTap: {}
        )
    }
    .padding()
    .background(Color.blue600)
} 
