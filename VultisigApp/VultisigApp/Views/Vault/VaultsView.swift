//
//  VaultsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI
import SwiftData

struct VaultsView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var showVaultsList: Bool
    @Binding var isEditingVaults: Bool
    
    @Query(sort: \Vault.order, order: .forward) var vaults: [Vault]
        
    @Environment(\.modelContext) var modelContext

    
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
            buttons
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
        .buttonStyle(BorderlessButtonStyle())
        .colorScheme(.dark)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundBlue)
    }
    
    var buttons: some View {
        ZStack {
            folderButton
            actionButtons
        }
        .frame(maxHeight: isEditingVaults ? 60 : 120)
        .clipped()
        .animation(.easeInOut, value: isEditingVaults)
    }
    
    var folderButton: some View {
        NavigationLink {
            CreateFolderView()
        } label: {
            OutlineButton(title: "createFolder")
        }
        .padding(16)
        .scaleEffect(showVaultsList ? 1 : 0)
        .opacity(showVaultsList ? 1 : 0)
        .buttonStyle(BorderlessButtonStyle())
        .offset(y: isEditingVaults ? 0 : 200)
    }
    
    var actionButtons: some View {
        VStack(spacing: 14) {
            addVaultButton
            importVaultButton
        }
        .padding(16)
        .offset(y: isEditingVaults ? 200 : 0)
        .animation(.easeInOut, value: isEditingVaults)
    }
    
    var addVaultButton: some View {
        NavigationLink {
            SetupQRCodeView(tssType: .Keygen, vault: nil)
        } label: {
            FilledButton(title: "addNewVault", icon: "plus")
        }
        .scaleEffect(showVaultsList ? 1 : 0)
        .opacity(showVaultsList ? 1 : 0)
        .buttonStyle(BorderlessButtonStyle())
    }
    
    var importVaultButton: some View {
        NavigationLink {
            ImportWalletView()
        } label: {
            OutlineButton(title: "importExistingVault")
        }
        .scaleEffect(showVaultsList ? 1 : 0)
        .opacity(showVaultsList ? 1 : 0)
        .buttonStyle(BorderlessButtonStyle())
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
        VaultsView(viewModel: HomeViewModel(), showVaultsList: .constant(true), isEditingVaults: .constant(false))
            .environmentObject(DeeplinkViewModel())
            .environmentObject(HomeViewModel())
    }
}
