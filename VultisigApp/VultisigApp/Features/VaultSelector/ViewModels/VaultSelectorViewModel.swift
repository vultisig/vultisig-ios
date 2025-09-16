//
//  VaultSelectorViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import Foundation

final class VaultSelectorViewModel: ObservableObject {
    @Published var folders: [Folder] = []
    @Published private var vaults: [Vault] = []
    @Published var filteredVaults: [Vault] = []
    
    func setup(folders: [Folder], vaults: [Vault]) {
        self.folders = folders
        self.vaults = vaults
        filterVaults()
    }
    
    func filterVaults() {
        let vaultNames = Set(folders.flatMap { $0.containedVaultNames })
        filteredVaults = vaults.filter { !vaultNames.contains($0.name) }
    }
}
