//
//  NavigationHomeEditButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI
import SwiftData

struct NavigationHomeEditButton: View {
    let vault: Vault?
    let showVaultsList: Bool
    let selectedFolder: Folder
    @Binding var isEditingVaults: Bool
    @Binding var isEditingFolders: Bool
    @Binding var showFolderDetails: Bool
    
    var tint: Color = Color.neutral0
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    @Query var folders: [Folder]
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            if showFolderDetails {
                folderHomeEditButton
            } else {
                vaultHomeEditButton
            }
        }
    }
    
    var folderHomeEditButton: some View {
        ZStack {
            if showVaultsList {
                foldersListEditButton
            } else {
                vaultDetailQRCodeButton
            }
        }
    }
    
    var vaultHomeEditButton: some View {
        ZStack {
            if showVaultsList {
                vaultsListEditButton
            } else {
                vaultDetailQRCodeButton
            }
        }
    }
    
    var vaultsListEditButton: some View {
        Button {
            withAnimation(.easeInOut) {
                isEditingVaults.toggle()
            }
        } label: {
            if isEditingVaults {
                doneButton
            } else {
                editButton
            }
        }
    }
    
    var foldersListEditButton: some View {
        ZStack {
            if isEditingFolders {
                deleteFolderButton
            } else {
                editFolderButton
            }
        }
    }
    
    var vaultDetailQRCodeButton: some View {
        NavigationLink {
            if let vault {
                VaultDetailQRCodeView(vault: vault)
            }
        } label: {
            NavigationQRCodeButton()
        }
    }
    
    var editButton: some View {
        NavigationEditButton()
    }
    
    var editFolderButton: some View {
        Button {
            withAnimation(.easeInOut) {
                isEditingFolders.toggle()
            }
        } label: {
            NavigationEditButton()
        }
    }
    
    var deleteFolderButton: some View {
        Button {
            deleteFolder()
        } label: {
            Image(systemName: "trash")
                .font(.body18MenloBold)
                .foregroundColor(.miamiMarmalade)
        }
    }
    
    var doneButton: some View {
        Text(NSLocalizedString("done", comment: ""))
            .foregroundColor(tint)
            .font(.body18MenloBold)
    }
    
    private func deleteFolder() {
        for folder in folders {
            if folder == selectedFolder {
                modelContext.delete(folder)
                do {
                    try modelContext.save()
                } catch {
                    print("Error: \(error)")
                }
                isEditingFolders = false
                showFolderDetails = false
                return
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            NavigationHomeEditButton(
                vault: Vault.example,
                showVaultsList: true,
                selectedFolder: Folder.example,
                isEditingVaults: .constant(true),
                isEditingFolders: .constant(true),
                showFolderDetails: .constant(true)
            )
            
            NavigationHomeEditButton(
                vault: Vault.example,
                showVaultsList: true,
                selectedFolder: Folder.example,
                isEditingVaults: .constant(false),
                isEditingFolders: .constant(true),
                showFolderDetails: .constant(true)
            )
        }
        .environmentObject(VaultDetailViewModel())
        .environmentObject(CoinSelectionViewModel())
    }
}
