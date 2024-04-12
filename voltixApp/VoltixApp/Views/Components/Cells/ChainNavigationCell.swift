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
    
    @State var balanceInFiat: String? = nil
    
    var body: some View {
        NavigationLink {
            ChainDetailView(group: group, vault: vault, balanceInFiat: balanceInFiat)
        } label: {
            ChainCell(group: group, balanceInFiat: $balanceInFiat)
        }
    }
}

#Preview {
    ChainNavigationCell(group: GroupedChain.example, vault: Vault.example)
}
