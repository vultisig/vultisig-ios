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
    @ObservedObject var viewModel: HomeViewModel
    
    @State var isEditing = false
    @State var selectedVaults: [Vault] = []
    @State var remaningVaults: [Vault] = []
    
    @State var showAlert = false
    @State var alertTitle = ""
    @State var alertDescription = ""
    
    @Query var folders: [Folder]
    @Query var vaults: [Vault]
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .alert(isPresented: $showAlert) {
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
            
            if isEditing {
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
                isEditing.toggle()
            }
        } label: {
            if isEditing {
                doneLabel
            } else {
                editIcon
            }
        }
    }
    
    var selectedVaultsList: some View {
        ForEach(selectedVaults, id: \.self) { vault in
            FolderDetailSelectedVaultCell(vault: vault, isEditing: isEditing)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
                .background(Color.backgroundBlue)
                .onTapGesture {
                    handleVaultSelection(for: vault)
                }
        }
        .padding(.horizontal, 16)
        .background(Color.backgroundBlue)
    }
    
    var vaultsTitle: some View {
        Text(NSLocalizedString("addVaultsToFolder", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
            .padding(.top, 22)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.backgroundBlue)
    }
    
    var vaultsList: some View {
        ForEach(remaningVaults, id: \.self) { vault in
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
            .frame(maxHeight: isEditing ? nil : 0)
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
            title: Text(NSLocalizedString(alertTitle, comment: "")),
            message: Text(NSLocalizedString(alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    func setData() {
        selectedVaults = []
        remaningVaults = []
        selectedVaults = getContainedVaults()
        remaningVaults = vaults.filter({ vault in
            !selectedVaults.contains(vault)
        })
    }
    
    func getContainedVaults() -> [Vault] {
        var containedVaults: [Vault] = []
        
        for containedVaultName in vaultFolder.containedVaultNames {
            for vault in vaults {
                if vault.name == containedVaultName {
                    containedVaults.append(vault)
                }
            }
        }
        
        return containedVaults
    }
    
    private func selectVault(_ vault: Vault) {
        selectedVaults.append(vault)
        vaultFolder.containedVaultNames = selectedVaults.map({ vault in
            vault.name
        })
    }
    
    private func handleVaultSelection(for vault: Vault) {
        if isEditing {
            removeVault(vault)
        } else {
            handleSelection(for: vault)
        }
    }
    
    private func removeVault(_ vault: Vault) {
        let count = selectedVaults.count
        
        guard count > 1 else {
            alertTitle = "error"
            alertDescription = "folderNeedsOneVault"
            showAlert = true
            return
        }
        
        for index in 0..<count {
            if selectedVaults[index] == vault {
                selectedVaults.remove(at: index)
                return
            }
        }
        
        vaultFolder.containedVaultNames = selectedVaults.map({ vault in
            vault.name
        })
    }
    
    private func handleSelection(for vault: Vault) {
        viewModel.setSelectedVault(vault)
        showVaultsList = false
        dismiss()
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
        viewModel: HomeViewModel()
    )
}
