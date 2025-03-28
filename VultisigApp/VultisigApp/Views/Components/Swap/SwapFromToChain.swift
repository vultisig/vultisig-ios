//
//  SwapFromToChain.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapFromToChain: View {
    let chain: Chain?
    
    var body: some View {
        HStack(spacing: 4) {
            icon
            title
            chevron
        }
    }
    
    var icon: some View {
        Image(chain?.logo ?? "")
            .resizable()
            .frame(width: 16, height: 16)
    }
    
    var title: some View {
        Text(chain?.name ?? "")
            .font(.body12BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.body10BrockmannMedium)
            .foregroundColor(.neutral0)
            .cornerRadius(32)
            .bold()
    }
}

#Preview {
    SwapFromToChain(chain: Chain.example)
}
