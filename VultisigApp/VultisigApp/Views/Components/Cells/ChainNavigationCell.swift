//
//  ChainNavigationCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct ChainNavigationCell: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault
    
    @State private var isActive = false
    @State var isEditingChains: Bool = false
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var body: some View {
        ZStack {
            cell
            navigationCell.opacity(0)
            
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .disabled(isEditingChains ? true : false)
        .padding(.vertical, 8)
    }
    
    var cell: some View {
        ChainCell(
            group: group,
            isEditingChains: $isEditingChains
        )
        .onTapGesture {
            isActive = true
        }
        .onLongPressGesture {
            copyAddress(for: group.name)
        }
    }
    
    var navigationCell: some View {
        NavigationLink(destination: ChainDetailView(group: group, vault: vault), isActive: $isActive) {
            ChainCell(group: group, isEditingChains: $isEditingChains)
        }
    }
}

#Preview {
    ChainNavigationCell(
        group: GroupedChain.example,
        vault: Vault.example
    )
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
