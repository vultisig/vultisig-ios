//
//  SwapChainCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapChainCell: View {
    let vault: Vault
    let chain: Chain
    let balance: String
    @Binding var selectedChain: Chain?
    @Binding var showSheet: Bool
    
    @State var isSelected = false
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            label
        }
        .buttonStyle(.borderless)
        .onAppear {
            setData()
        }
    }
    
    var label: some View {
        VStack(spacing: 0) {
            content
            GradientListSeparator()
        }
        .background(isSelected ? Color.blue400 : Color.blue600)
    }
    
    var content: some View {
        HStack {
            icon
            title
            Spacer()
            balanceInfo
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
    
    var icon: some View {
        Image(chain.logo)
            .resizable()
            .frame(width: 32, height: 32)
    }
    
    var title: some View {
        Text(chain.name)
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var balanceInfo: some View {
        Text(balance)
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    private func setData() {
        isSelected = chain == selectedChain
    }
    
    private func handleTap() {
        selectedChain = chain
        showSheet = false
    }
}

#Preview {
    SwapChainCell(
        vault: .example,
        chain: Chain.example,
        balance: "10000",
        selectedChain: .constant(Chain.example),
        showSheet: .constant(true)
    )
}
