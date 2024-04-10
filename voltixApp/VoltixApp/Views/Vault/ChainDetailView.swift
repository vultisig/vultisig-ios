//
//  ChainDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-10.
//

import SwiftUI

struct ChainDetailView: View {
    let title: String
    let group: GroupedChain
    let vault: Vault
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(title, comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton()
            }
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 0) {
                actions
                header
                cells
            }
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.vertical, 30)
        }
    }
    
    var actions: some View {
        HStack {
            
        }
    }
    
    var header: some View {
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
}

#Preview {
    ChainDetailView(title: "Ethereum", group: GroupedChain.example, vault: Vault.example)
}
