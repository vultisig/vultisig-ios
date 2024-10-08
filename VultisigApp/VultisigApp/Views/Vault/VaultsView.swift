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
    @Query(sort: \Folder.order, order: .forward) var folders: [Folder]
        
    @Environment(\.modelContext) var modelContext
    
    @State var showFolderDetails: Bool = false
    @State var selectedFolder: Folder = .example

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
        .onDisappear {
            isEditingVaults = false
        }
    }
    
    var view: some View {
        content
            .navigationDestination(isPresented: $showFolderDetails) {
                FolderDetailView(
                    vaultFolder: $selectedFolder,
                    showVaultsList: $showVaultsList,
                    viewModel: viewModel
                )
            }
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
            if folders.count>0 {
                getTitle(for: "folders")
                foldersList
                getTitle(for: "vaults")
            }
            vaultsList
        }
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
        .colorScheme(.dark)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundBlue)
    }
    
    var foldersList: some View {
        ForEach(folders, id: \.self) { folder in
            Button(action: {
                handleFolderSelection(for: folder)
            }, label: {
                FolderCell(folder: folder, isEditing: isEditingVaults)
            })
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)
            .background(Color.backgroundBlue)
        }
        .onMove(perform: isEditingVaults ? moveFolder : nil)
    }
    
    var vaultsList: some View {
        ForEach(vaults, id: \.self) { vault in
            getButton(for: vault)
        }
        .onMove(perform: isEditingVaults ? move : nil)
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
            CreateFolderView(count: folders.count)
        } label: {
            OutlineButton(title: "createFolder")
        }
        .padding(.horizontal, 16)
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
    
    func moveFolder(from: IndexSet, to: Int) {
        var s = folders.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
                item.order = index
        }
        try? self.modelContext.save()
    }
    
    private func handleFolderSelection(for folder: Folder) {
        guard !isEditingVaults else {
            return
        }
        
        selectedFolder = folder
        showFolderDetails = true
    }
    
    private func getTitle(for text: String) -> some View {
        Text(NSLocalizedString(text, comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .background(Color.backgroundBlue)
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
