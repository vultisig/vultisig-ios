//
//  ChainNavigationCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct ChainNavigationCell: View {
    let group: GroupedChain
    let vault: Vault
    @Binding var isEditingChains: Bool
    
    @State var balanceInFiat: String? = nil
    
    var body: some View {
        NavigationLink {
            ChainDetailView(group: group, vault: vault, balanceInFiat: balanceInFiat)
        } label: {
            ChainCell(group: group, balanceInFiat: $balanceInFiat, isEditingChains: $isEditingChains)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .disabled(isEditingChains ? true : false)
        .padding(.vertical, 8)
    }
}

#Preview {
    ChainNavigationCell(group: GroupedChain.example, vault: Vault.example, isEditingChains: .constant(true))
}
