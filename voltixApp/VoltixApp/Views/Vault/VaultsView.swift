//
//  VaultsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI
import SwiftData

struct VaultsView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var showVaultsList: Bool
    
    @Query var vaults: [Vault]
    
    var body: some View {
        VStack {
            ZStack {
                Background()
                view
            }
            .frame(maxHeight: showVaultsList ? .none : 0)
            .clipped()
            
            Spacer()
        }
        .allowsHitTesting(showVaultsList)
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
                    VaultCell(vault: vault)
                        .onTapGesture {
                            viewModel.setSelectedVault(vault)
                            showVaultsList = false
                        }
                }
            }
            .padding(.top, 30)
        }
    }
    
    var addVaultButton: some View {
        NavigationLink {
            CreateVaultView(showBackButton: true)
        } label: {
            FilledButton(title: "addNewVault", icon: "plus")
                .padding(16)
        }
        .scaleEffect(showVaultsList ? 1 : 0)
        .opacity(showVaultsList ? 1 : 0)
    }
}

#Preview {
    ZStack {
        Background()
        VaultsView(viewModel: HomeViewModel(), showVaultsList: .constant(false))
    }
}
