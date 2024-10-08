//
//  CreateFolderView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-03.
//

import SwiftUI
import SwiftData

struct CreateFolderView: View {
    @Binding var folders: [VaultFolder]
    
    @State var name = ""
    @State var selectedVaults: [Vault] = []
    @State var vaultFolder: VaultFolder? = nil
    
    @State var showAlert = false
    @State var alertTitle = ""
    @State var alertDescription = ""
    
    @Query var vaults: [Vault]
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
        }
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var content: some View {
        ScrollView {
            folderName
            vaultList
        }
    }
    
    var button: some View {
        Button {
            createFolder()
        } label: {
            FilledButton(title: "create")
                .padding(16)
        }
    }
    
    var folderName: some View {
        VStack(alignment: .leading, spacing: 12) {
            folderNameTitle
            folderNameTextField
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var folderNameTitle: some View {
        Text(NSLocalizedString("folderName", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
    }
    
    var folderNameTextField: some View {
        TextField(
            NSLocalizedString("typeHere", comment: ""),
            text: $name
        )
        .font(.body14Menlo)
        .foregroundColor(.neutral0)
        .submitLabel(.done)
        .padding(12)
        .padding(.vertical, 3)
        .background(Color.blue600)
        .cornerRadius(12)
        .colorScheme(.dark)
        .borderlessTextFieldStyle()
    }
    
    var vaultList: some View {
        VStack(alignment: .leading, spacing: 12) {
            vaultsTitle
            list
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
    }
    
    var vaultsTitle: some View {
        Text(NSLocalizedString("addVaultsToFolder", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
            .padding(.top, 22)
    }
    
    var list: some View {
        VStack(spacing: 6) {
            ForEach(vaults, id: \.self) { vault in
                FolderVaultCell(vault: vault, selectedVaults: $selectedVaults)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(alertTitle, comment: "")),
            message: Text(NSLocalizedString(alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func createFolder() {
        guard runChecks() else {
            return
        }
        
        vaultFolder = VaultFolder(
            folderName: name,
            containedVaults: selectedVaults
        )
        
        guard let vaultFolder else {
            alertTitle = "error"
            alertDescription = "somethingWentWrongTryAgain"
            showAlert = true
            return
        }
        
        folders.append(vaultFolder)
        
        dismiss()
    }
    
    private func runChecks() -> Bool {
        if name.isEmpty {
            alertTitle = "emptyField"
            alertDescription = "enterValidFolderName"
            showAlert = true
            return false
        }
        
        if selectedVaults.isEmpty {
            alertTitle = "error"
            alertDescription = "selectAtleastOneVault"
            showAlert = true
            return false
        }
        
        return true
    }
}

#Preview {
    CreateFolderView(folders: .constant([.example]))
}
