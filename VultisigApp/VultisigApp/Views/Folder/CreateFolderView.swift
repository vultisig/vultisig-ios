//
//  CreateFolderView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-03.
//

import SwiftUI
import SwiftData

struct CreateFolderView: View {
    let count: Int
    
    @Query var vaults: [Vault]
    @Query var folders: [Folder]
    
    @StateObject var viewModel = CreateFolderViewModel()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
        }
        .alert(isPresented: $viewModel.showAlert) {
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
            text: $viewModel.name
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
                FolderVaultCell(vault: vault, selectedVaults: $viewModel.selectedVaults)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(viewModel.alertTitle, comment: "")),
            message: Text(NSLocalizedString(viewModel.alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    func createFolder() {
        guard viewModel.runChecks(folders) else {
            return
        }
        
        viewModel.setupFolder(count)
        
        guard let vaultFolder = viewModel.vaultFolder else {
            viewModel.showErrorAlert()
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            modelContext.insert(vaultFolder)
            dismiss()
        }
    }
}

#Preview {
    CreateFolderView(count: 0)
}
