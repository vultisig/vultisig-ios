//
//  VaultRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum VaultBackupOrigin: Hashable {
    /// Backup opened from Vault Settings. Behaves as `.standard`; only the look differs.
    case vaultSettings
    case standard
    case appLockSettings
}

extension VaultBackupOrigin {
    /// Settings entries use the redesigned backup screens; keygen, onboarding, home and the
    /// monthly reminder keep the original ones.
    var usesSettingsLook: Bool {
        self != .standard
    }
}

enum VaultRoute: Hashable {
    case upgradeVault(vault: Vault)
    case serverBackup(vault: Vault)
    case backupPasswordOptions(
        tssType: TssType,
        backupType: VaultBackupType,
        isNewVault: Bool,
        origin: VaultBackupOrigin = .standard
    )
    case backupSelection(vault: Vault, origin: VaultBackupOrigin = .standard)
    case backupPasswordScreen(
        tssType: TssType,
        backupType: VaultBackupType,
        isNewVault: Bool,
        origin: VaultBackupOrigin = .standard
    )
    case backupSuccess(tssType: TssType, vault: Vault)
    case createVault(showBackButton: Bool)
    case swap(fromCoin: Coin?, toCoin: Coin?, vault: Vault)
    case allDevicesUpgrade(vault: Vault, hasReviewedBackups: Bool = false)
    case vaultShareBackups(vault: Vault)
    case reshare(vault: Vault)
    case passwordHint(vault: Vault)
    case vaultDetails(vault: Vault, devicesInfo: [DeviceInfo])
    case renameVault(vault: Vault, vaults: [Vault], folders: [Folder])
    case deleteVault(vault: Vault, devicesInfo: [DeviceInfo])
    case advancedSettings(vault: Vault)
    case customMessage(vault: Vault)
    case customRPC(vault: Vault)
    case customRPCDetail(chain: Chain)
    case onChainSecurity
    case chainDetail(chain: Chain, vault: Vault)
    case defiChain(chain: Chain, vault: Vault)
}
