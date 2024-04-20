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
    @Binding var isEditingVaults: Bool
    
    @Query var vaults: [Vault]
    
    @State var orderedVaults = [Vault]()
    
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
        .onAppear {
            orderedVaults = vaults
        }
    }
    
    var view: some View {
        VStack {
            list
            Spacer()
            addVaultButton
        }
    }
    
    var list: some View {
        List {
            ForEach(orderedVaults, id: \.self) { vault in
                getButton(for: vault)
            }
            .onMove(perform: isEditingVaults ? move: nil)
            .background(Color.backgroundBlue)
        }
        .listStyle(PlainListStyle())
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
    
    private func getButton(for vault: Vault) -> some View {
        Button {
            handleSelection(for: vault)
        } label: {
            VaultCell(vault: vault, isEditing: isEditingVaults)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.vertical, 8)
        .disabled(isEditingVaults ? true : false)
    }
    
    private func handleSelection(for vault: Vault) {
        viewModel.setSelectedVault(vault)
        showVaultsList = false
    }
    
    func move(from: IndexSet, to: Int) {
        orderedVaults.move(fromOffsets: from, toOffset: to)
    }
}

#Preview {
    ZStack {
        Background()
        VaultsView(viewModel: HomeViewModel(), showVaultsList: .constant(false), isEditingVaults: .constant(true))
    }
}
