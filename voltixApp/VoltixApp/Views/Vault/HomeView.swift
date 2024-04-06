//
//  HomeView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct HomeView: View {
    @State var selectedVault: Vault? = nil
    @State var showVaultsList = true
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                menuButton
            }
            
            ToolbarItem(placement: .principal) {
                navigationTitle
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton()
            }
        }
    }
    
    var view: some View {
        ZStack {
            if let vault = selectedVault {
                VaultDetailView(showVaultsList: $showVaultsList, vault: vault)
            }
            
            VaultsView(selectedVault: $selectedVault, showVaultsList: $showVaultsList)
        }
    }
    
    var navigationTitle: some View {
        ZStack {
            HStack {
                title
                
                if selectedVault != nil {
                    Image(systemName: "chevron.up")
                        .font(.body8Menlo)
                        .bold()
                        .foregroundColor(.neutral0)
                        .rotationEffect(.degrees(showVaultsList ? 0 : 180))
                }
            }
        }
        .onTapGesture {
            switchView()
        }
    }
    
    var title: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("main", comment: "Home view title"))
                .font(.body)
                .bold()
                .foregroundColor(.neutral0)
            
            Text(selectedVault?.name ?? NSLocalizedString("vault", comment: "Home view title"))
                .font(.body)
                .bold()
                .foregroundColor(.neutral0)
        }
        .offset(y: showVaultsList ? 9 : -10)
        .frame(height: 20)
        .clipped()
    }
    
    var menuButton: some View {
        NavigationLink {
            SettingsView()
        } label: {
            NavigationMenuButton()
        }
    }
    
    private func switchView() {
        guard selectedVault != nil else {
            return
        }
        
        withAnimation(.easeInOut) {
            showVaultsList.toggle()
        }
    }
}

#Preview {
    HomeView()
}
