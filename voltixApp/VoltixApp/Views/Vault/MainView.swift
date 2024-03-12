//
//  MainView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct MainView: View {
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
            if showVaultsList {
                VaultsView(selectedVault: $selectedVault, showVaultsList: $showVaultsList)
            } else if let vault = selectedVault {
                VaultDetailView(presentationStack: .constant([]), vault: vault)
            }
        }
    }
    
    var navigationTitle: some View {
        ZStack {
            if showVaultsList {
                getTitle(
                    for: NSLocalizedString("main", comment: "Home view title"),
                    image: "chevron.up",
                    showImage: selectedVault != nil
                )
            } else {
                getTitle(
                    for: selectedVault?.name ?? NSLocalizedString("vault", comment: "Home view title"),
                    image: "chevron.down"
                )
            }
        }
        .onTapGesture {
            switchView()
        }
    }
    
    func getTitle(for title: String, image: String, showImage: Bool = true) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .bold()
                .foregroundColor(.neutral0)
            
            if showImage {
                Image(systemName: image)
                    .font(.body8Menlo)
                    .bold()
                    .foregroundColor(.neutral0)
            }
        }
    }
    
    private func switchView() {
        guard selectedVault != nil else {
            return
        }
        
        showVaultsList.toggle()
    }
}

#Preview {
    MainView()
}
