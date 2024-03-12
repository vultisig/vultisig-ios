//
//  VaultDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI

struct VaultDetailView: View {
    @Binding var presentationStack: [CurrentScreen]
    let vault: Vault
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var body: some View {
        ZStack {
            background
            view
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
        VStack {
            ScrollView {
                list
                addButton
            }
            scanButton
        }
    }
    
    var list: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.coins, id: \.self) { coin in
                CoinCell(presentationStack: $presentationStack, coin: coin)
            }
        }
        .padding(.top, 30)
    }
    
    var addButton: some View {
        FilledButton(title: "chooseTokens", icon: "plus")
            .padding(16)
    }
    
    var scanButton: some View {
        ZStack {
            Circle()
                .foregroundColor(.turquoise600)
                .frame(width: 60, height: 60)
            
            Image(systemName: "camera")
                .font(.title30MenloUltraLight)
                .foregroundColor(.blue600)
        }
    }
    
    private func setData() {
        viewModel.fetchCoins(for: vault)
    }
}

#Preview {
    VaultDetailView(presentationStack: .constant([]), vault: Vault.example)
        .environmentObject(VaultDetailViewModel())
}
