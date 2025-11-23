//
//  HomeViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

class HomeViewModel: ObservableObject {
    @AppStorage("vaultName") var vaultName: String = ""
    @AppStorage("selectedPubKeyECDSA") var selectedPubKeyECDSA: String = ""
    @AppStorage("showVaultBalance") var hideVaultBalance: Bool = false
    
    @Published var selectedVault: Vault? = nil
    @Published var filteredVaults: [Vault] = []
    
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    
    var vaultBalanceText: String {
        balanceText(for: selectedVault)
    }
    
    var defiBalanceText: String {
        defiBalanceText(for: selectedVault)
    }
    
    func balanceText(for vaults: [Vault]) -> String {
        guard !hideVaultBalance else {
            return String.hideBalanceText
        }
        
        return vaults
            .map(\.coins.totalBalanceInFiatDecimal)
            .reduce(0, +)
            .formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
    }
    
    func balanceText(for vault: Vault?) -> String {
        guard !hideVaultBalance else {
            return String.hideBalanceText
        }
        
        return vault?.coins.totalBalanceInFiatString ?? ""
    }
    
    func defiBalanceText(for vault: Vault?) -> String {
        guard !hideVaultBalance else {
            return String.hideBalanceText
        }
        
        return vault?.coins
            .filter { vault?.defiChains.contains($0.chain) ?? false }
            .totalDefiBalanceInFiatString ?? ""
    }

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
        ApplicationState.shared.currentVault = vault
    }
    
    func filterVaults(vaults: [Vault], folders: [Folder]) {
        filteredVaults = getFilteredVaults(vaults: vaults, folders: folders)
    }
    
    func getFilteredVaults(vaults: [Vault], folders: [Folder]) -> [Vault] {
        let vaultNames = Set(folders.flatMap { $0.containedVaultNames })
        
        return vaults.filter({ vault in
            !vaultNames.contains(vault.name)
        })
    }
}
