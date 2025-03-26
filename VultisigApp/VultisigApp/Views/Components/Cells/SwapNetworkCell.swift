//
//  SwapNetworkCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapNetworkCell: View {
    let chain: CoinMeta?
    @Binding var selectedChain: Chain?
    @Binding var showSheet: Bool
    
    @State var isSelected = false
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            label
        }
        .onAppear {
            setData()
        }
    }
    
    var label: some View {
        VStack(spacing: 0) {
            content
            Separator()
                .opacity(0.2)
        }
        .background(isSelected ? Color.blue400 : Color.blue600)
    }
    
    var content: some View {
        HStack {
            icon
            title
            Spacer()
            
            if isSelected {
                check
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
    
    var icon: some View {
        Image(chain?.chain.logo ?? "")
            .resizable()
            .frame(width: 32, height: 32)
    }
    
    var title: some View {
        Text(chain?.chain.name ?? "")
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var check: some View {
        Image(systemName: "checkmark")
            .font(.body12BrockmannMedium)
            .foregroundColor(.alertTurquoise)
            .frame(width: 24, height: 24)
            .background(Color.blue600)
            .cornerRadius(32)
            .bold()
    }
    
    private func setData() {
        isSelected = chain?.chain == selectedChain
    }
    
    private func handleTap() {
        selectedChain = chain?.chain
        showSheet = false
    }
}

#Preview {
    SwapNetworkCell(
        chain: CoinMeta.example,
        selectedChain: .constant(Chain.example),
        showSheet: .constant(true)
    )
}
