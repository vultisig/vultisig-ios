//
//  FolderDetailView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import SwiftUI
import SwiftData

struct FolderDetailView: View {
    @Binding var vaultFolder: Folder
    @Binding var showVaultsList: Bool
    @Binding var showFolderDetails: Bool
    @ObservedObject var viewModel: HomeViewModel
    
    @Query var folders: [Folder]
    @Query var vaults: [Vault]
    
    @StateObject var folderViewModel = FolderDetailViewModel()
    
    @Environment(\.dismiss) var dismiss
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
        .onChange(of: vaultFolder.containedVaultNames) { oldValue, newValue in
            setData()
        }
    }
    
    var content: some View {
        List {
            selectedVaultsList
            
            if folderViewModel.isEditing {
                vaultsTitle
                vaultsList
            }
        }
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
        .colorScheme(.dark)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundBlue)
    }
    
    var navigationEditButton: some View {
        Button {
            withAnimation {
                folderViewModel.isEditing.toggle()
            }
        } label: {
            if folderViewModel.isEditing {
                doneLabel
            } else {
                editIcon
            }
        }
    }
    
    var selectedVaultsList: some View {
        ForEach(folderViewModel.selectedVaults.sorted(by: {
            $0.order < $1.order
        }), id: \.self) { vault in
            FolderDetailSelectedVaultCell(vault: vault, isEditing: folderViewModel.isEditing)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
                .background(Color.backgroundBlue)
                .onTapGesture {
                    handleVaultSelection(for: vault)
                }
        }
        .onMove(perform: folderViewModel.isEditing ? move : nil)
        .padding(.horizontal, 16)
        .background(Color.backgroundBlue)
    }
    
    var vaultsTitle: some View {
        Text(NSLocalizedString("addVaultsToFolder", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
            .padding(.top, 22)
            .padding(.horizontal, 16)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.backgroundBlue)
    }
    
    var vaultsList: some View {
        ForEach(folderViewModel.remaningVaults, id: \.self) { vault in
            FolderDetailRemainingVaultCell(vault: vault)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
                .background(Color.backgroundBlue)
                .onTapGesture {
                    selectVault(vault)
                }
        }
        .padding(.horizontal, 16)
        .background(Color.backgroundBlue)
    }
    
    var button: some View {
        Button {
            deleteFolder()
        } label: {
            label
        }
    }
    
    var label: some View {
        FilledButton(title: "deleteFolder", background: Color.miamiMarmalade)
            .padding(16)
            .edgesIgnoringSafeArea(.bottom)
            .frame(maxHeight: folderViewModel.isEditing ? nil : 0)
            .clipped()
            .background(Color.backgroundBlue)
    }
    
    var editIcon: some View {
        Image(systemName: "square.and.pencil")
            .foregroundColor(Color.neutral0)
            .font(.body18MenloBold)
    }
    
    var doneLabel: some View {
        Text(NSLocalizedString("done", comment: ""))
            .foregroundColor(Color.neutral0)
            .font(.body18MenloBold)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(folderViewModel.alertTitle, comment: "")),
            message: Text(NSLocalizedString(folderViewModel.alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func setData() {
        folderViewModel.setData(
            vaults: vaults,
            vaultFolder: vaultFolder,
            filteredVaults: viewModel.filteredVaults
        )
    }
    
    private func handleVaultSelection(for vault: Vault) {
        if folderViewModel.isEditing {
            removeVault(vault)
        } else {
            handleSelection(for: vault)
        }
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
        
        folderViewModel.removeVaultAtIndex(count: count, vault: vault)
        
        vaultFolder.containedVaultNames = folderViewModel.selectedVaults.map({ vault in
            vault.name
        })
    }
    
    private func handleSelection(for vault: Vault) {
        viewModel.setSelectedVault(vault)
        dismiss()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            showVaultsList = false
        }
    }
    
    private func deleteFolder() {
        for folder in folders {
            if folder == vaultFolder {
                modelContext.delete(folder)
                do {
                    try modelContext.save()
                } catch {
                    print("Error: \(error)")
                }
                dismiss()
                return
            }
        }
    }
}

#Preview {
    FolderDetailView(
        vaultFolder: .constant(Folder.example),
        showVaultsList: .constant(false), 
        showFolderDetails: .constant(true),
        viewModel: HomeViewModel()
    )
}
