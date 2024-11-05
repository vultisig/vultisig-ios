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
    @Binding var isEditingFolders: Bool
    @Binding var showFolderDetails: Bool
    @Binding var selectedFolder: Folder
    
    @Query(sort: \Vault.order, order: .forward) var vaults: [Vault]
    @Query(sort: \Folder.order, order: .forward) var folders: [Folder]
        
    @Environment(\.modelContext) var modelContext

    var body: some View {
        ZStack {
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
            .onChange(of: isEditingVaults, { oldValue, newValue in
                filterVaults()
            })
            .onAppear {
                setData()
            }
            .onDisappear {
                isEditingVaults = false
            }
        }
    }
    
    var view: some View {
        ZStack{
            content
            
            if showFolderDetails {
                FolderDetailView(
                    selectedFolder: selectedFolder, 
                    vaultFolder: $selectedFolder,
                    showVaultsList: $showVaultsList,
                    showFolderDetails: $showFolderDetails, 
                    isEditingFolders: $isEditingFolders,
                    viewModel: viewModel
                )
            }
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
            getFolderButton(for: folder)
        }
        .onMove(perform: isEditingVaults ? moveFolder : nil)
    }
    
    var vaultsList: some View {
        ForEach(viewModel.filteredVaults.sorted {
            $0.order < $1.order
        }, id: \.self) { vault in
            getButton(for: vault)
        }
        .onMove(perform: isEditingVaults ? moveVaults : nil)
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
            CreateFolderView(
                count: folders.count,
                filteredVaults: viewModel.filteredVaults
            )
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
        }
        .padding(16)
        .offset(y: isEditingVaults ? 200 : 0)
        .animation(.easeInOut, value: isEditingVaults)
    }
    
    var addVaultButton: some View {
        NavigationLink {
            CreateVaultView(showBackButton: true)
        } label: {
            FilledButton(title: "addNewVault", icon: "plus")
        }
        .scaleEffect(showVaultsList ? 1 : 0)
        .opacity(showVaultsList ? 1 : 0)
        .buttonStyle(BorderlessButtonStyle())
    }
    
    private func getFolderButton(for folder: Folder) -> some View {
        Button(action: {
            handleFolderSelection(for: folder)
        }, label: {
            FolderCell(folder: folder, isEditing: isEditingVaults)
        })
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.vertical, 8)
        .background(Color.backgroundBlue)
        .disabled(isEditingVaults ? true : false)
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
        
        filterVaults()
    }
    
    private func filterVaults() {
        guard !isEditingVaults else {
            return
        }
        
        viewModel.filterVaults(vaults: vaults, folders: folders)
    }
    
    private func handleSelection(for vault: Vault) {
        viewModel.setSelectedVault(vault)
        showVaultsList = false
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
    
    func moveVaults(from: IndexSet, to: Int) {
        var filteredVaults = viewModel.filteredVaults.sorted(by: { $0.order < $1.order })
        filteredVaults.move(fromOffsets: from, toOffset: to)
        for (index, item) in filteredVaults.enumerated() {
            item.order = index
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
}

#Preview {
    ZStack {
        Background()
        VaultsView(
            viewModel: HomeViewModel(),
            showVaultsList: .constant(true),
            isEditingVaults: .constant(false), 
            isEditingFolders: .constant(false),
            showFolderDetails: .constant(false),
            selectedFolder: .constant(.example)
        )
        .environmentObject(DeeplinkViewModel())
        .environmentObject(HomeViewModel())
    }
}
