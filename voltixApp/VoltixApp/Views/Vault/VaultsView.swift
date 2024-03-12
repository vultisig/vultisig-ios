//
//  VaultsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI
import SwiftData

struct VaultsView: View {
    @Binding var presentationStack: [CurrentScreen]
    
    @Query var vaults: [Vault]
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("main", comment: "Home view title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationMenuButton()
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
        VStack {
            list
            Spacer()
            addVaultButton
        }
    }
    
    var list: some View {
        ScrollView {
            LazyVStack {
                ForEach(vaults, id: \.self) { vault in
                    VaultCell(presentationStack: $presentationStack, vault: vault)
                }
            }
            .padding(.top, 30)
        }
    }
    
    var addVaultButton: some View {
        NavigationLink {
            CreateVaultView(presentationStack: .constant([]))
        } label: {
            FilledButton(title: "addNewVault", icon: "plus")
                .padding(16)
        }
    }
}

#Preview {
    VaultsView(presentationStack: .constant([]))
}
