//
//  VaultDefiChainsService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

// Enables Defi chains for the first time for vaults that were created before Defi features where released
struct VaultDefiChainsService {
    @AppStorage("enabled_vaults") private var enabledVaults: [String] = []
    
    func enableDefiChainsIfNeeded(for vault: Vault) async {
        guard !enabledVaults.contains(vault.pubKeyECDSA) else {
            return
        }
        
        vault.defiChains = vault.chains.filter { CoinAction.defiChains.contains($0) }
        do {
            try await Storage.shared.save()
            enabledVaults.append(vault.pubKeyECDSA)
        } catch {
            print("Failed to save DeFi chains for vault: \(error)")
        }
    }
}
