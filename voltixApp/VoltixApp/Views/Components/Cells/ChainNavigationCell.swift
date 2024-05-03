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
        }
        .disabled(isEditingChains ? true : false)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
}

#Preview {
    ChainNavigationCell(group: GroupedChain.example, vault: Vault.example, isEditingChains: .constant(true))
}
