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
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationMenuButton()
            }
            
            ToolbarItem(placement: .principal) {
                navigationTitle
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        ZStack {
//            if showVaultsList {
//                VaultsView(selectedVault: $selectedVault, showVaultsList: $showVaultsList)
//            } else if let vault = selectedVault {
//                VaultDetailView(presentationStack: .constant([]), vault: vault)
//            }
            if let vault = selectedVault {
                VaultDetailView(presentationStack: .constant([]), vault: vault)
            }
            
            VaultsView(selectedVault: $selectedVault, showVaultsList: $showVaultsList)
        }
    }
    
    var navigationTitle: some View {
        ZStack {
            HStack {
                Text(getTitle())
                    .font(.body)
                    .bold()
                    .foregroundColor(.neutral0)
                
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
    
    private func getTitle() -> String {
        let title: String
        
        if showVaultsList {
            title = NSLocalizedString("main", comment: "Home view title")
        } else {
            title = selectedVault?.name ?? NSLocalizedString("vault", comment: "Home view title")
        }
        return title
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
