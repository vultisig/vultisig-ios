//
//  VaultDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI

struct VaultDetailView: View {
    @Binding var presentationStack: [CurrentScreen]
    @Binding var showVaultsList: Bool
    let vault: Vault
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    @State var showSheet = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            background
            view
            scanButton
        }
        .onAppear {
            setData()
        }
        .onChange(of: vault) {
            setData()
        }
        .sheet(isPresented: $showSheet, content: {
            NavigationView {
                TokenSelectionView(showTokenSelectionSheet: $showSheet)
            }
        })
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
        .opacity(showVaultsList ? 0 : 1)
    }
    
    var list: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.coinsGroupedByChains, id: \.address) { group in
                ChainCell(group: group)
            }
        }
        .padding(.top, 30)
    }
    
    var addButton: some View {
        Button {
            showSheet.toggle()
        } label: {
            FilledButton(title: "chooseTokens", icon: "plus")
        }
        .padding(16)
        .padding(.bottom, 150)
    }
    
    var scanButton: some View {
        ZStack {
            Circle()
                .foregroundColor(.blue800)
                .frame(width: 80, height: 80)
                .opacity(0.8)
            
            Circle()
                .foregroundColor(.turquoise600)
                .frame(width: 60, height: 60)
            
            Image(systemName: "camera")
                .font(.title30MenloUltraLight)
                .foregroundColor(.blue600)
        }
        .opacity(showVaultsList ? 0 : 1)
    }
    
    private func setData() {
        viewModel.fetchCoins(for: vault)
    }
}

#Preview {
    VaultDetailView(presentationStack: .constant([]), showVaultsList: .constant(false), vault: Vault.example)
        .environmentObject(VaultDetailViewModel())
}
