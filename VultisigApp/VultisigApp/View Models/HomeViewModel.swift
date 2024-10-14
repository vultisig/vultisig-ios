//
//  HomeViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    @AppStorage("vaultName") var vaultName: String = ""
    @AppStorage("selectedPubKeyECDSA") var selectedPubKeyECDSA: String = ""
    @AppStorage("showVaultBalance") var hideVaultBalance: Bool = false
    
    @Published var selectedVault: Vault? = nil
    @Published var filteredVaults: [Vault] = []

    func loadSelectedVault(for vaults: [Vault]) {
        if vaultName.isEmpty || selectedPubKeyECDSA.isEmpty {
            setSelectedVault(vaults.first)
            return
        }
        
        for vault in vaults {
            if vaultName==vault.name && selectedPubKeyECDSA==vault.pubKeyECDSA {
                setSelectedVault(vault)
                return
            }
        }
        
        setSelectedVault(vaults.first)
    }
    
    func setSelectedVault(_ vault: Vault?) {
        selectedVault = vault
        vaultName = vault?.name ?? ""
        selectedPubKeyECDSA = vault?.pubKeyECDSA ?? ""
    }
    
    func filterVaults(vaults: [Vault], folders: [Folder]) {
        let vaultNames = Set(folders.flatMap { $0.containedVaultNames })
        
        filteredVaults = vaults.filter({ vault in
            !vaultNames.contains(vault.name)
        })
    }
}
