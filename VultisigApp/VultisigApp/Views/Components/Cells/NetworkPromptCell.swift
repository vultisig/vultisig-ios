//
//  NetworkPromptCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

struct NetworkPromptCell: View {
    let network: NetworkPromptType
    let isSelected: Bool
    
    var body: some View {
        ZStack {
#if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneCell
            } else {
                padCell
            }
#elseif os(macOS)
            padCell
#endif
        }
    }
    
    var phoneCell: some View {
        HStack(spacing: 8) {
            network.getImage()
                .font(.body14Menlo)
                .foregroundColor(.turquoise600)
            
            Text(NSLocalizedString(network.rawValue, comment: ""))
                .font(.body10MenloBold)
                .foregroundColor(.neutral0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue200 : Color.blue400)
        .cornerRadius(20)
        .overlay (
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.neutral0, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        .padding(.horizontal, 8)
    }
    
    var padCell: some View {
        HStack(spacing: 8) {
            network.getImage()
                .font(.body20Menlo)
                .foregroundColor(.turquoise600)
            
            Text(NSLocalizedString(network.rawValue, comment: ""))
                .font(.body14MenloBold)
                .foregroundColor(.neutral0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isSelected ? Color.blue200 : Color.blue400)
        .cornerRadius(20)
        .overlay (
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.neutral0, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        .padding(.horizontal, 8)
    }
}

#Preview {
    NetworkPromptCell(network: .Internet, isSelected: true)
}
