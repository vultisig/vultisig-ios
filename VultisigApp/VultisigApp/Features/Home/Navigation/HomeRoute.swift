//
//  HomeRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/12/2025.
//

enum HomeRoute: Hashable {
    case home(showingVaultSelector: Bool)
    case vaultAction(action: VaultAction, sendTx: SendTransaction, vault: Vault)
}
