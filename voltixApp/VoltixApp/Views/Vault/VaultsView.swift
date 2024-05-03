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
    
    @Query(sort: \Vault.order) var vaults: [Vault]
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    
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
            setData()
        }
    }
    
    var view: some View {
        content
    }
    
    var content: some View {
        VStack {
            list
            Spacer()
            addVaultButton
        }
    }
    
    var list: some View {
        List {
            ForEach(vaults, id: \.self) { vault in
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
    
    private func setData() {
        for index in 0..<vaults.count {
            vaults[index].setOrder(index)
        }
    }
    
    private func handleSelection(for vault: Vault) {
        viewModel.setSelectedVault(vault)
        showVaultsList = false
    }
    
    func move(from: IndexSet, to: Int) {
        let fromIndex = from.first ?? 0
        
        if fromIndex<to {
            moveDown(fromIndex: fromIndex, toIndex: to-1)
        } else {
            moveUp(fromIndex: fromIndex, toIndex: to)
        }
    }
    
    private func moveDown(fromIndex: Int, toIndex: Int) {
        for index in fromIndex...toIndex {
            vaults[index].order = vaults[index].order-1
        }
        vaults[fromIndex].order = toIndex
    }
    
    private func moveUp(fromIndex: Int, toIndex: Int) {
        vaults[fromIndex].order = toIndex
        for index in toIndex...fromIndex {
            vaults[index].order = vaults[index].order+1
        }
    }
}

#Preview {
    ZStack {
        Background()
        VaultsView(viewModel: HomeViewModel(), showVaultsList: .constant(false), isEditingVaults: .constant(true))
            .environmentObject(DeeplinkViewModel())
    }
}
