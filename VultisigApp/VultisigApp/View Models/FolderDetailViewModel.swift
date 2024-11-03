//
//  FolderDetailViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-08.
//

import SwiftUI

class FolderDetailViewModel: ObservableObject {
    @Published var selectedVaults: [Vault] = []
    @Published var remaningVaults: [Vault] = []
    
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertDescription = ""
    
    func setData(vaults: [Vault], vaultFolder: Folder, filteredVaults: [Vault]) {
        selectedVaults = []
        remaningVaults = []
        selectedVaults = getContainedVaults(vaults: vaults, vaultFolder: vaultFolder)
        remaningVaults = filteredVaults.filter({ vault in
            !selectedVaults.contains(vault)
        })
    }
    
    func getContainedVaults(vaults: [Vault], vaultFolder: Folder) -> [Vault] {
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
    
    func toggleAlert() {
        alertTitle = "error"
        alertDescription = "folderNeedsOneVault"
        showAlert = true
    }
    
    func removeVaultAtIndex(count: Int, vault: Vault) {
        for index in 0..<count {
            if selectedVaults[index] == vault {
                selectedVaults.remove(at: index)
                return
            }
        }
    }
}
