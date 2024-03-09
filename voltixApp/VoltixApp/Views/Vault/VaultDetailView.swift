//
//  VaultDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI

struct VaultDetailView: View {
    let vault: Vault
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(vault.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton()
            }
        }
        .onAppear {
            setData()
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        ScrollView {
            list
            addButton
        }
        .padding(.top, 30)
    }
    
    var list: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.coins, id: \.self) { coin in
                CoinCell(coin: coin)
            }
        }
    }
    
    var addButton: some View {
        FilledButton(title: "chooseTokens", icon: "plus")
            .padding(16)
    }
    
    private func setData() {
        viewModel.fetchCoins(for: vault)
    }
}

#Preview {
    VaultDetailView(vault: Vault.example)
        .environmentObject(VaultDetailViewModel())
}
