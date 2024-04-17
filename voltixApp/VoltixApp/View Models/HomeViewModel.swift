//
//  HomeViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import Foundation

@MainActor
class HomeViewModel: ObservableObject {
    @Published var selectedVault: Vault? = nil
    
    let selectedVaultKey = "selectedVault"
    
    func loadSelectedVault(for vaults: [Vault]) {
        guard let data = getSelectedVault() else {
            selectedVault = vaults.first
            setSelectedVault(selectedVault)
            return
        }
        
        selectedVault = data
    }
    
    func setSelectedVault(_ vault: Vault?) {
        do {
            let encodedData = try JSONEncoder().encode(vault)
            UserDefaults.standard.set(encodedData, forKey: selectedVaultKey)
            selectedVault = vault
        } catch {
            print("Error encoding person:", error)
        }
    }
    
    func getSelectedVault() -> Vault? {
        if let savedData = UserDefaults.standard.data(forKey: selectedVaultKey) {
            do {
                let vault = try JSONDecoder().decode(Vault.self, from: savedData)
                return vault
            } catch {
                print("Error decoding person:", error)
                return nil
            }
        }
        return nil
    }
}
