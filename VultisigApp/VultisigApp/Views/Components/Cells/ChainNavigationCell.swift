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
    let showBalance: Bool
    
    @State private var isActive = false
    @State var isEditingChains: Bool = false
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    @State var showAlert = false
    
    var body: some View {
        ZStack {
            cell
            navigationCell.opacity(0)
            
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .disabled(isEditingChains ? true : false)
        .padding(.vertical, 8)
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var cell: some View {
        ChainCell(
            group: group,
            showBalance: showBalance,
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
            ChainCell(group: group, showBalance: showBalance, isEditingChains: $isEditingChains)
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("addressCopied", comment: "")),
            message: Text(group.address),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func copyAddress() {
        showAlert = true
        let pasteboard = UIPasteboard.general
        pasteboard.string = group.address
    }
}

#Preview {
    ChainNavigationCell(
        group: GroupedChain.example,
        vault: Vault.example, 
        showBalance: true
    )
    .environmentObject(VaultDetailViewModel())
}
