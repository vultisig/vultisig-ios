//
//  CreateFolderViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-08.
//

import SwiftUI

class CreateFolderViewModel: ObservableObject {
    @Published var name = "" {
        didSet {
            folderNameError = nil
        }
    }
    @Published var selectedVaults: [Vault] = []
    @Published var vaultFolder: Folder? = nil
    
    @Published var folderNameError: String?
    
    var saveButtonDisabled: Bool {
        name.isEmpty || selectedVaults.isEmpty
    }
    
    func runChecks(_ folders: [Folder]) -> Bool {
        if name.isEmpty {
            folderNameError = "enterValidFolderName".localized
            return false
        }
        
        if selectedVaults.isEmpty {
            folderNameError = "selectAtleastOneVault".localized
            return false
        }
        
        for folder in folders {
            if folder.folderName == name {
                folderNameError = "sameNameFolderDescription".localized
                return false
            }
        }
        
        folderNameError = nil
        return true
    }
    
    func showErrorAlert() {
        folderNameError = "somethingWentWrongTryAgain".localized
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
