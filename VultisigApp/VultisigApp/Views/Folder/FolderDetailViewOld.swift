//
//  FolderDetailViewOld.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import SwiftUI
import SwiftData

struct FolderDetailViewOld: View {
    let selectedFolder: Folder
    @Binding var vaultFolder: Folder
    @Binding var showVaultsList: Bool
    @Binding var showFolderDetails: Bool
    @Binding var isEditingFolders: Bool
    @ObservedObject var viewModel: HomeViewModel
    
    @Query var folders: [Folder]
    @Query var vaults: [Vault]
    
    @State var folderName: String = ""
    @StateObject var folderViewModel = FolderDetailViewModel()
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .alert(isPresented: $folderViewModel.showAlert) {
            alert
        }
        .onAppear {
            setData()
        }
    }
    
    var view: some View {
        ZStack(alignment: .bottom) {
            content
            saveButton
        }
    }
    
    var content: some View {
        List {
            spacer
            
            if isEditingFolders {
                folderRename
                listTitle
            }
            
            selectedVaultsList
            
            if isEditingFolders {
                vaultsTitle
                vaultsList
            }
        }
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
        .colorScheme(.dark)
        .scrollContentBackground(.hidden)
        .padding(.bottom, isEditingFolders ? 80 : 0)
        .background(Theme.colors.bgPrimary)
    }
    
    var spacer: some View {
        Background()
            .frame(height: 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .background(Theme.colors.bgPrimary)
    }
    
    var folderRename: some View {
        VStack(alignment: .leading, spacing: 12) {
            folderNameTitle
            folderNameTextField
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .background(Theme.colors.bgPrimary)
        .onAppear {
            setupFolder()
        }
    }
    
    var folderNameTitle: some View {
        Text(NSLocalizedString("folderName", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
    }
    
    var folderNameTextField: some View {
        TextField(
            NSLocalizedString("typeHere", comment: ""),
            text: $folderName
        )
        .font(Theme.fonts.bodyMRegular)
        .foregroundColor(Theme.colors.textPrimary)
        .submitLabel(.done)
        .padding(12)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(12)
        .colorScheme(.dark)
        .borderlessTextFieldStyle()
        .autocorrectionDisabled()
    }
       
    var selectedVaultsList: some View {
        ForEach(folderViewModel.selectedVaults.sorted(by: {
            $0.order < $1.order
        }), id: \.self) { vault in
            FolderDetailSelectedVaultCell(vault: vault, isEditing: isEditingFolders, handleVaultSelection: handleVaultSelection)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
                .background(Theme.colors.bgPrimary)
        }
        .onMove(perform: isEditingFolders ? move : nil)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgPrimary)
    }
    
    var listTitle: some View {
        Text(NSLocalizedString("currentVaults", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .padding(.top, 22)
            .padding(.horizontal, 16)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.colors.bgPrimary)
    }
    
    var vaultsTitle: some View {
        Text(NSLocalizedString("addVaultsToFolder", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .padding(.top, 22)
            .padding(.horizontal, 16)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.colors.bgPrimary)
    }
    
    var vaultsList: some View {
        ForEach(folderViewModel.remainingVaults, id: \.self) { vault in
            FolderDetailremainingVaultsCell(vault: vault)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
                .background(Theme.colors.bgPrimary)
                .onTapGesture {
                    selectVault(vault)
                }
        }
        .padding(.horizontal, 16)
        .background(Theme.colors.bgPrimary)
    }
    
    var saveButton: some View {
        PrimaryButton(title: "saveChanges") {
            saveFolder()
        }
        .padding(16)
        .edgesIgnoringSafeArea(.bottom)
        .frame(maxHeight: isEditingFolders ? nil : 0)
        .clipped()
        .background(Theme.colors.bgPrimary)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(folderViewModel.alertTitle, comment: "")),
            message: Text(NSLocalizedString(folderViewModel.alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func setData() {
        filterVaults()
        folderViewModel.setData(
            vaults: vaults,
            vaultFolder: vaultFolder,
            filteredVaults: viewModel.filteredVaults
        )
    }
    
    private func filterVaults() {
        viewModel.filterVaults(vaults: vaults, folders: folders)
    }
    
    private func handleVaultSelection(for vault: Vault) {
        if isEditingFolders {
            removeVault(vault)
        } else {
            handleSelection(for: vault)
        }
        filterVaults()
    }
    
    private func move(from: IndexSet, to: Int) {
        var s = folderViewModel.selectedVaults.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
            item.order = index
        }
        try? self.modelContext.save()
    }
    
    private func selectVault(_ vault: Vault) {
        folderViewModel.selectedVaults.append(vault)
        vaultFolder.containedVaultNames = folderViewModel.selectedVaults.map({ vault in
            vault.name
        })
    }
    
    private func removeVault(_ vault: Vault) {
        let count = folderViewModel.selectedVaults.count
        
        guard count > 1 else {
            folderViewModel.toggleAlert()
            return
        }
        
        folderViewModel.removeVault(vault: vault)
        
        vaultFolder.containedVaultNames = folderViewModel.selectedVaults.map({ vault in
            vault.name
        })
    }
    
    private func handleSelection(for vault: Vault) {
        viewModel.setSelectedVault(vault)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            showVaultsList = false
        }
    }
    
    private func setupFolder() {
        folderName = selectedFolder.folderName
    }
    
    private func saveFolder() {
        filterVaults()
        
        withAnimation(.easeInOut) {
            isEditingFolders = false
        }
        
        for folder in folders {
            if folder.id == selectedFolder.id {
                folder.folderName = folderName
                return
            }
        }
    }
}

#Preview {
    FolderDetailViewOld(
        selectedFolder: Folder.example, 
        vaultFolder: .constant(Folder.example),
        showVaultsList: .constant(false),
        showFolderDetails: .constant(true), 
        isEditingFolders: .constant(true),
        viewModel: HomeViewModel()
    )
}
