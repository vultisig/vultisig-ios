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
    @Binding var showAlert: Bool
    
    @State private var isActive = false
    @State var isEditingChains: Bool = false
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
            copyAddress()
        }
    }
    
    var navigationCell: some View {
        NavigationLink(destination: ChainDetailView(group: group, vault: vault), isActive: $isActive) {
            ChainCell(group: group, isEditingChains: $isEditingChains)
        }
    }
    
    private func copyAddress() {
        showAlert = true
#if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = group.address
#elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(group.address, forType: .string)
#endif
    }
}

#Preview {
    ChainNavigationCell(
        group: GroupedChain.example,
        vault: Vault.example, 
        showAlert: .constant(false)
    )
    .environmentObject(VaultDetailViewModel())
}
