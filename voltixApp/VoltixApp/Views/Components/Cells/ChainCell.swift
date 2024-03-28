//
//  ChainCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct ChainCell: View {
    let group: GroupedChain
    let vault: Vault
    
    @State var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            main
            
            if isExpanded {
                cells
            }
        }
        .padding(.vertical, 4)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .clipped()
    }
    
    var main: some View {
        Button(action: {
            expandCell()
        }, label: {
            card
        })
    }
    
    var card: some View {
        ChainHeaderCell(group: group)
    }
    
    var cells: some View {
        ForEach(group.coins, id: \.self) { coin in
            VStack(spacing: 0) {
                Separator()
                CoinCell(coin: coin, group: group, vault: vault)
            }
        }
    }
    
    private func expandCell() {
        withAnimation {
            isExpanded.toggle()
        }
    }
}

#Preview {
    ScrollView {
        ChainCell(group: GroupedChain.example, vault: Vault.example)
    }
}
