//
//  FolderDetailViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-08.
//

import SwiftUI

class FolderDetailViewModel: ObservableObject {
    @Published var allVaults: [Vault] = []
    @Published var selectedVaults: [Vault] = []
    @Published var remainingVaults: [Vault] = []

    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertDescription = ""

    private let logic = FolderDetailLogic()

    func setData(vaults: [Vault], vaultFolder: Folder, filteredVaults: [Vault]) {
        allVaults = vaults
        selectedVaults = logic.getContainedVaults(vaults: vaults, vaultFolder: vaultFolder)
        remainingVaults = filteredVaults.filter({ vault in
            !selectedVaults.contains(vault)
        })
    }

    func toggleAlert() {
        alertTitle = "error"
        alertDescription = "folderNeedsOneVault"
        showAlert = true
    }

    func removeVault(vault: Vault) {
        selectedVaults.removeAll(where: { $0 == vault })
        remainingVaults.append(vault)
    }

    func addVault(vault: Vault) {
        selectedVaults.append(vault)
        remainingVaults.removeAll(where: { $0 == vault })
    }
}

// MARK: - FolderDetailLogic

struct FolderDetailLogic {
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
}
