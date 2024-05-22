//
//  ChainNavigationCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct ChainNavigationCell: View {
    let group: GroupedChain
    let vault: Vault
    
    @Binding var isEditingChains: Bool

    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var body: some View {
        ZStack {
            navigationCell.opacity(0)
            cell
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .disabled(isEditingChains ? true : false)
        .padding(.vertical, 8)
    }
    
    var cell: some View {
        ChainCell(group: group, isEditingChains: $isEditingChains)
    }
    
    var navigationCell: some View {
        NavigationLink {
            ChainDetailView(group: group, vault: vault)
        } label: {
            ChainCell(group: group, isEditingChains: $isEditingChains)
        }
    }
}

#Preview {
    ChainNavigationCell(
        group: GroupedChain.example,
        vault: Vault.example,
        isEditingChains: .constant(true)
    )
    .environmentObject(VaultDetailViewModel())
}
