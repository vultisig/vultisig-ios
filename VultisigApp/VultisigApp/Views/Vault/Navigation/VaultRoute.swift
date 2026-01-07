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
    case swap(fromCoin: Coin?, toCoin: Coin?, vault: Vault)
    case allDevicesUpgrade(vault: Vault)
    case vaultShareBackups(vault: Vault)
    case reshare(vault: Vault)
    case passwordHint(vault: Vault)
    case vaultDetails(vault: Vault, devicesInfo: [DeviceInfo])
    case renameVault(vault: Vault, vaults: [Vault], folders: [Folder])
    case deleteVault(vault: Vault, devicesInfo: [DeviceInfo])
    case advancedSettings(vault: Vault)
    case customMessage(vault: Vault)
    case onChainSecurity
    case chainDetail(group: GroupedChain, vault: Vault)
    case defiChain(group: GroupedChain, vault: Vault)
}
