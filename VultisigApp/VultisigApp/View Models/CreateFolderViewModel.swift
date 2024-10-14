//
//  CreateFolderViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-08.
//

import SwiftUI

class CreateFolderViewModel: ObservableObject {
    @Published var name = ""
    @Published var selectedVaults: [Vault] = []
    @Published var vaultFolder: Folder? = nil
    
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertDescription = ""
    
    func runChecks(_ folders: [Folder]) -> Bool {
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
        
        for folder in folders {
            if folder.folderName == name {
                alertTitle = "sameNameFolder"
                alertDescription = "sameNameFolderDescription"
                showAlert = true
                return false
            }
        }
        
        return true
    }
    
    func showErrorAlert() {
        alertTitle = "error"
        alertDescription = "somethingWentWrongTryAgain"
        showAlert = true
    }
    
    func setupFolder(_ count: Int) {
        vaultFolder = Folder(
            folderName: name,
            containedVaultNames: selectedVaults.map({ vault in
                vault.name
            }),
            order: count
        )
    }
}
