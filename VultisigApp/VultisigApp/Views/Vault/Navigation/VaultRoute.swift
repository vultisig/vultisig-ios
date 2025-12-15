//
//  VaultRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum VaultRoute: Hashable {
    case upgradeVault(vault: Vault, isFastVault: Bool)
    case serverBackup(vault: Vault)
    case backupPasswordOptions(tssType: TssType, backupType: VaultBackupType, isNewVault: Bool)
    case backupSelection(vault: Vault)
    case backupPasswordScreen(tssType: TssType, backupType: VaultBackupType, isNewVault: Bool)
    case backupSuccess(tssType: TssType, vault: Vault)
    case createVault(showBackButton: Bool)
    case home(vault: Vault, showVaultsList: Bool, shouldJoinKeygen: Bool)
}
